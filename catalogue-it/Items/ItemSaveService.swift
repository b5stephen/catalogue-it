//
//  ItemSaveService.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Item Save Service

/// Applies the edit sheet's drafts by diffing against what is stored, so an unchanged field or
/// photo is not written. Updating in place keeps CloudKit record identities stable; delete
/// and recreate let a rejected or late creation lose fields and photos.
///
/// - A `FieldValue` matches its draft by `FieldDefinition.fieldID`. Values with a nil
///   definition are left alone: it may not have synced yet.
/// - Duplicate values for one definition (a merge artefact) collapse to one.
/// - An `ItemPhoto` matches by `PhotoDraft.existingPhotoID`.
/// - `modifiedDate` moves only for a real content change.
///
/// With the `EditBaseline` the sheet loaded, the diff is three-way, since a draft is a copy
/// of the item as of opening and may be stale. A draft equal to its baseline leaves the
/// stored value alone:
/// - An untouched field is not written, though one with no stored value is still created so
///   the item stays reachable by a custom sort on it.
/// - An untouched photo keeps its stored caption and position, and stays deleted if deleted
///   elsewhere. Only photos the user saw and removed are deleted. A touched draft whose photo
///   is gone is inserted afresh.
/// - Untouched notes are not written.
/// Without a baseline (creating, duplicating), every draft is applied.
@MainActor
enum ItemSaveService {

    struct Outcome {
        let item: CatalogueItem
        let fieldsChanged: Bool
        let photosChanged: Bool
        let notesChanged: Bool
        /// Computed only when `photosChanged`; `nil` then means no photos remain.
        let coverThumbnailData: Data?

        /// Creating an item always counts.
        var didChange: Bool { fieldsChanged || photosChanged || notesChanged }
    }

    /// Saves so new models hold permanent identifiers before any view renders them.
    static func save(
        existing: CatalogueItem?,
        in catalogue: Catalogue,
        notes: String,
        fieldDrafts: [FieldValueDraft],
        photoDrafts: [PhotoDraft],
        baseline: EditBaseline? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws -> Outcome {
        let item: CatalogueItem
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalisedNotes: String? = trimmedNotes.isEmpty ? nil : trimmedNotes
        var notesChanged = false

        if let existing {
            item = existing
            let notesTouched = baseline.map { $0.notes != notes } ?? true
            if notesTouched, existing.notes != normalisedNotes {
                existing.notes = normalisedNotes
                notesChanged = true
            }
        } else {
            item = CatalogueItem(notes: normalisedNotes)
            // One clock reading, so a never-edited item has `modifiedDate == createdDate` exactly.
            item.createdDate = now
            // Insert before relating: set on an un-inserted model, the catalogue FK reaches the store
            // lazily and the list's post-save count, which filters on it, can miss the row.
            context.insert(item)
            item.catalogue = catalogue
            notesChanged = true
        }

        // Fetched, not read off the relationships: `context.delete` on a relationship instance
        // can crash snapshot creation — see DeletionService.
        let storedValues = try existing.map { try fetchFieldValues(of: $0, context: context) } ?? []
        let storedPhotos = try existing.map { try fetchPhotos(of: $0, context: context) } ?? []

        let sortedDefs = catalogue.sortedFieldDefinitions
        let (fieldValues, fieldsChanged) = applyFieldDrafts(
            fieldDrafts, to: item, stored: storedValues, baseline: baseline?.fieldDrafts,
            definitions: sortedDefs, context: context)
        ItemDerivedColumns.refresh(on: item, fieldValues: fieldValues, definitions: sortedDefs)

        let (photosChanged, coverThumbnailData) = applyPhotoDrafts(
            photoDrafts, to: item, stored: storedPhotos, baseline: baseline?.photoDrafts, context: context)

        if fieldsChanged || photosChanged || notesChanged {
            item.modifiedDate = now
        }

        // Not left to autosave: new models need permanent identifiers before the list renders
        // them, and ItemPaginationController only hears explicit saves.
        try context.save()

        return Outcome(
            item: item,
            fieldsChanged: fieldsChanged,
            photosChanged: photosChanged,
            notesChanged: notesChanged,
            coverThumbnailData: coverThumbnailData
        )
    }

    /// Saves only if something changed.
    @discardableResult
    static func updateNotes(_ notes: String, on item: CatalogueItem, context: ModelContext, now: Date = .now) throws -> Bool {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalised: String? = trimmed.isEmpty ? nil : trimmed
        guard item.notes != normalised else { return false }
        item.notes = normalised
        item.modifiedDate = now
        try context.save()
        return true
    }

    // MARK: - Fetching

    private static func fetchFieldValues(of item: CatalogueItem, context: ModelContext) throws -> [FieldValue] {
        let itemID = item.persistentModelID
        return try context.fetch(FetchDescriptor<FieldValue>(
            predicate: #Predicate { $0.item?.persistentModelID == itemID }
        ))
    }

    private static func fetchPhotos(of item: CatalogueItem, context: ModelContext) throws -> [ItemPhoto] {
        let itemID = item.persistentModelID
        return try context.fetch(FetchDescriptor<ItemPhoto>(
            predicate: #Predicate { $0.item?.persistentModelID == itemID }
        ))
    }

    // MARK: - Field Values

    /// The values in draft order, and whether any user-visible value changed.
    private static func applyFieldDrafts(
        _ drafts: [FieldValueDraft],
        to item: CatalogueItem,
        stored: [FieldValue],
        baseline: [FieldValueDraft]?,
        definitions: [FieldDefinition],
        context: ModelContext
    ) -> (values: [FieldValue], changed: Bool) {
        var changed = false
        let baselineByFieldID = baseline.map { drafts in
            Dictionary(drafts.map { ($0.fieldID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let definitionsByFieldID = Dictionary(definitions.map { ($0.fieldID, $0) }, uniquingKeysWith: { first, _ in first })

        // Orphans (definition nil) are kept: their definition may be in transit. The survivor is
        // chosen as every reader chooses (`SortKeyEncoder.preferredValue`), so two devices saving
        // the same item keep the same row — keeping different ones would delete both.
        var valuesByFieldID: [UUID: FieldValue] = [:]
        for fieldID in Set(stored.compactMap { $0.fieldDefinition?.fieldID }) {
            guard let keep = SortKeyEncoder.preferredValue(forFieldID: fieldID, among: stored) else { continue }
            valuesByFieldID[fieldID] = keep
            for value in stored where value !== keep && value.fieldDefinition?.fieldID == fieldID {
                context.delete(value)
                changed = true
            }
        }

        var result: [FieldValue] = []
        for draft in drafts {
            let fieldID = draft.fieldID
            let touched = baselineByFieldID?[fieldID].map { !draft.hasSameValue(as: $0) } ?? true
            let value: FieldValue
            if let existing = valuesByFieldID[fieldID] {
                value = existing
                if !touched {
                    result.append(value)
                    continue
                }
                if value.fieldType != draft.fieldType {
                    // The definition's type changed under this value.
                    value.fieldType = draft.fieldType
                    value.textValue = nil
                    value.numberValue = nil
                    value.dateValue = nil
                    value.boolValue = nil
                    changed = true
                }
            } else {
                // The field was removed on another device while the sheet was open. Relate to the
                // catalogue's own instance, not the draft's possibly stale one.
                guard let definition = definitionsByFieldID[fieldID] else { continue }
                // Insert before relating: the custom-sort count filters on this FK.
                value = FieldValue(fieldDefinition: nil, fieldType: draft.fieldType)
                context.insert(value)
                value.fieldDefinition = definition
                value.item = item
                valuesByFieldID[fieldID] = value
                // Upkeep, not an edit: mustn't move modifiedDate.
                if touched { changed = true }
            }
            if apply(draft, to: value), touched { changed = true }
            result.append(value)
        }
        return (result, changed)
    }

    /// Returns whether it wrote.
    private static func apply(_ draft: FieldValueDraft, to value: FieldValue) -> Bool {
        switch draft.fieldType {
        case .text, .optionList:
            let trimmed = draft.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let text: String? = trimmed.isEmpty ? nil : trimmed
            guard value.textValue != text else { return false }
            value.textValue = text
        case .number:
            guard value.numberValue != draft.numberValue else { return false }
            value.numberValue = draft.numberValue
        case .date:
            guard value.dateValue != draft.dateValue else { return false }
            value.dateValue = draft.dateValue
        case .boolean:
            guard value.boolValue != draft.boolValue else { return false }
            value.boolValue = draft.boolValue
        }
        return true
    }

    // MARK: - Photos

    /// Drafts are numbered 0…n−1 on load, so a stored set with a gap never matches them.
    /// Priorities are rewritten for every draft only when the order or membership changed, so
    /// a touched caption can't collide with an untouched sibling's stored priority.
    private static func applyPhotoDrafts(
        _ drafts: [PhotoDraft],
        to item: CatalogueItem,
        stored: [ItemPhoto],
        baseline: [PhotoDraft]?,
        context: ModelContext
    ) -> (changed: Bool, coverThumbnailData: Data?) {
        var changed = false
        let existingByID = Dictionary(stored.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        let baselineByID = baseline.map { drafts in
            Dictionary(drafts.compactMap { draft in draft.existingPhotoID.map { ($0, draft) } },
                       uniquingKeysWith: { first, _ in first })
        }
        let sequenceChanged = baseline.map { $0.map(\.existingPhotoID) != drafts.map(\.existingPhotoID) } ?? true
        var kept: Set<PersistentIdentifier> = []
        var remaining: [ItemPhoto] = []

        for draft in drafts {
            let trimmedCaption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let caption: String? = trimmedCaption.isEmpty ? nil : trimmedCaption
            let touched = draft.existingPhotoID.flatMap { baselineByID?[$0] }.map { $0 != draft } ?? true

            if let id = draft.existingPhotoID, let photo = existingByID[id] {
                kept.insert(id)
                remaining.append(photo)
                if sequenceChanged, photo.priority != draft.priority {
                    photo.priority = draft.priority
                    changed = true
                }
                guard touched else { continue }
                if photo.caption != caption {
                    photo.caption = caption
                    changed = true
                }
                // Only fires if an editor replaced the bytes; avoids re-uploading an untouched asset.
                if photo.imageData != draft.imageData {
                    photo.imageData = draft.imageData
                    photo.thumbnailData = draft.imageData.makeThumbnail()
                    changed = true
                }
            } else {
                // Untouched and deleted on another device.
                guard touched else { continue }
                let photo = ItemPhoto(
                    imageData: draft.imageData,
                    thumbnailData: draft.imageData.makeThumbnail(),
                    priority: draft.priority,
                    caption: caption
                )
                context.insert(photo)
                photo.item = item
                remaining.append(photo)
                changed = true
            }
        }

        for (id, photo) in existingByID where !kept.contains(id) {
            // Anything the sheet didn't show arrived from another device while it was open.
            if let baselineByID, baselineByID[id] == nil {
                remaining.append(photo)
                continue
            }
            context.delete(photo)
            changed = true
        }

        guard changed else { return (false, nil) }
        // From what the item holds now: the drafts can name a photo deleted elsewhere or miss one
        // added elsewhere.
        let cover = remaining.min { $0.priority < $1.priority }
        return (true, cover.flatMap { $0.thumbnailData ?? $0.imageData.makeThumbnail() })
    }
}
