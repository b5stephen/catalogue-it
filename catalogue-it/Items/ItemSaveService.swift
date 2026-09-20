//
//  ItemSaveService.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Item Save Service

/// Applies the edit sheet's drafts to a `CatalogueItem` by diffing them against what is
/// already stored, so an unchanged field or photo produces no write at all.
///
/// This replaces "delete every FieldValue and ItemPhoto, recreate them from the drafts".
/// Locally that was one save; through CloudKit it was N record deletions, N creations and a
/// fresh upload of every photo, each an independent record with its own fate. Deletions
/// always succeed; the creations could be rejected (Production schema behind the model),
/// land in a later import pass, or collide with an edit made on another device — all of
/// which reached users as "I added a photo and my other fields disappeared". Updating in
/// place keeps record identities stable, so CloudKit's per-property merge does what it says.
///
/// Rules the diff follows:
/// - A `FieldValue` is matched to its draft by `FieldDefinition.fieldID`. Values whose
///   definition is `nil` are left alone: the definition may simply not have synced yet.
/// - Duplicate values for one definition (possible after a merge) collapse to one.
/// - An `ItemPhoto` is matched by `PhotoDraft.existingPhotoID`.
/// - `modifiedDate` moves only for a real content change, never for derived-column upkeep.
///
/// The diff is three-way when the caller passes the `EditBaseline` the sheet was loaded
/// from. The drafts are a copy of the item as of opening the sheet, not a statement of the
/// user's intent, and an edit merged in from another device while the sheet is open makes
/// that copy stale: a two-way diff against the store would see the stale draft differ and
/// write it back, undoing the other device's edit. With a baseline, a draft the user did
/// not touch (equal to its baseline) leaves the stored value alone, whatever it now holds:
/// - An untouched field is not written. One with no stored value yet is still created, so
///   the item stays reachable by a custom sort on that field.
/// - An untouched photo keeps its stored caption and position; if it was deleted elsewhere
///   it stays deleted. Only photos the user saw and removed are deleted, so one added
///   elsewhere while the sheet was open survives. A touched draft whose photo is gone is
///   inserted afresh, since the user's edit would otherwise be lost.
/// - Untouched notes are not written.
/// Without a baseline (creating, duplicating), every draft is applied.
@MainActor
enum ItemSaveService {

    struct Outcome {
        let item: CatalogueItem
        let fieldsChanged: Bool
        let photosChanged: Bool
        let notesChanged: Bool
        /// Thumbnail of the first photo by priority, computed only when `photosChanged`.
        /// `nil` alongside `photosChanged == true` means the item now has no photos.
        let coverThumbnailData: Data?

        /// True when the user changed something. Creating an item always counts.
        var didChange: Bool { fieldsChanged || photosChanged || notesChanged }
    }

    /// Creates `existing == nil` or updates an item from the drafts, then saves the context
    /// so new models hold permanent identifiers before any view renders them.
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
            // Both stamps from the one clock reading, so a never-edited item satisfies
            // `modifiedDate == createdDate` exactly.
            item.createdDate = now
            // Insert before wiring the relationship. Set on an un-inserted model, the
            // catalogue FK reaches the store lazily, and the item list's post-save count
            // (which filters on that FK) can miss the row — so the first item in a fresh
            // catalogue sometimes never appeared.
            context.insert(item)
            item.catalogue = catalogue
            notesChanged = true
        }

        // Children are fetched rather than read off the relationship arrays because the
        // diff deletes some of them, and `context.delete` on an instance that came from a
        // relationship (stale, or resurrected by an undo) crashes snapshot creation — see
        // DeletionService. A new item has no children to fetch.
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

        // Save now rather than leaving it to autosave: newly inserted models need permanent
        // identifiers before the list renders them, and ItemPaginationController only hears
        // explicit saves.
        try context.save()

        return Outcome(
            item: item,
            fieldsChanged: fieldsChanged,
            photosChanged: photosChanged,
            notesChanged: notesChanged,
            coverThumbnailData: coverThumbnailData
        )
    }

    /// Replaces an item's notes on their own (the detail screen's notes sheet).
    /// Returns whether anything changed; the context is saved only if so.
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

    /// Returns the item's field values in draft order, after updating, inserting and
    /// de-duplicating as needed, and whether any user-visible value changed.
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

        // One value per definition. Extras are a merge artefact and are dropped; orphans
        // (definition nil) are kept, since their definition may still be in transit. The
        // survivor is chosen the way every reader chooses (`SortKeyEncoder.preferredValue`),
        // so two devices saving the same item keep the same row — keeping different ones
        // would delete both.
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
            // No baseline, or a field that wasn't in the sheet, counts as touched.
            let touched = baselineByFieldID?[fieldID].map { !draft.hasSameValue(as: $0) } ?? true
            let value: FieldValue
            if let existing = valuesByFieldID[fieldID] {
                value = existing
                if !touched {
                    result.append(value)
                    continue
                }
                if value.fieldType != draft.fieldType {
                    // The definition's type changed under this value; nothing stored under the
                    // old type is meaningful any more.
                    value.fieldType = draft.fieldType
                    value.textValue = nil
                    value.numberValue = nil
                    value.dateValue = nil
                    value.boolValue = nil
                    changed = true
                }
            } else {
                // The field was removed from the catalogue (on another device, while the
                // sheet was open): nothing to hold the value, whether typed or not. The
                // catalogue's own instance is related, not the draft's possibly stale one.
                guard let definition = definitionsByFieldID[fieldID] else { continue }
                // Same insert-then-relate order as the item: the custom-sort count filters on
                // the fieldDefinition FK.
                value = FieldValue(fieldDefinition: nil, fieldType: draft.fieldType)
                context.insert(value)
                value.fieldDefinition = definition
                value.item = item
                // A second draft for the same definition updates this one rather than
                // inserting again.
                valuesByFieldID[fieldID] = value
                // Creating the row for an untouched field is upkeep (it keeps the item
                // reachable by a custom sort), not an edit: it must not move modifiedDate.
                if touched { changed = true }
            }
            if apply(draft, to: value), touched { changed = true }
            result.append(value)
        }
        return (result, changed)
    }

    /// Writes the draft's typed value onto `value` if it differs. Returns whether it did.
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

    /// Position is a property of the *sequence*, not of one photo: the drafts are numbered
    /// 0…n−1 on load, so a stored set with a gap (one deleted elsewhere) never matches
    /// them. Priorities are therefore rewritten for every draft when the user reordered,
    /// added or removed something — the sequence of ids differs from the baseline — and
    /// left alone otherwise, so a touched caption can never hand its photo a priority that
    /// collides with an untouched sibling's stored one.
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
        /// What the item holds after this save, for the cover.
        var remaining: [ItemPhoto] = []

        for draft in drafts {
            let trimmedCaption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let caption: String? = trimmedCaption.isEmpty ? nil : trimmedCaption
            // A newly picked photo has no baseline entry and so always counts as touched.
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
                // The draft's bytes came from this photo, so this only fires if an editor
                // replaced them. Comparing avoids re-uploading an untouched asset.
                if photo.imageData != draft.imageData {
                    photo.imageData = draft.imageData
                    photo.thumbnailData = draft.imageData.makeThumbnail()
                    changed = true
                }
            } else {
                // Untouched and gone from the store: deleted on another device, and the
                // user expressed no wish to keep it.
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
            // With a baseline, only a photo the sheet showed can have been removed by the
            // user; anything else arrived from another device while the sheet was open.
            if let baselineByID, baselineByID[id] == nil {
                remaining.append(photo)
                continue
            }
            context.delete(photo)
            changed = true
        }

        guard changed else { return (false, nil) }
        // From what the item actually holds now — not the drafts, which can still name a
        // photo deleted elsewhere or miss one added elsewhere.
        let cover = remaining.min { $0.priority < $1.priority }
        return (true, cover.flatMap { $0.thumbnailData ?? $0.imageData.makeThumbnail() })
    }
}
