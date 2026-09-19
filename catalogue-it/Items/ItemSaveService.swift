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
/// - An `ItemPhoto` is matched by `PhotoDraft.existingPhotoID`; a draft whose photo no
///   longer exists (deleted on another device meanwhile) is inserted afresh so the user's
///   intent survives.
/// - `modifiedDate` moves only for a real content change, never for derived-column upkeep.
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
        context: ModelContext,
        now: Date = .now
    ) throws -> Outcome {
        let item: CatalogueItem
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalisedNotes: String? = trimmedNotes.isEmpty ? nil : trimmedNotes
        var notesChanged = false

        if let existing {
            item = existing
            if existing.notes != normalisedNotes {
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

        let sortedDefs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
        let (fieldValues, fieldsChanged) = applyFieldDrafts(fieldDrafts, to: item, stored: storedValues, context: context)
        refreshDerivedColumns(on: item, fieldValues: fieldValues, definitions: sortedDefs)

        let (photosChanged, coverThumbnailData) = applyPhotoDrafts(photoDrafts, to: item, stored: storedPhotos, context: context)

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
        context: ModelContext
    ) -> (values: [FieldValue], changed: Bool) {
        var changed = false

        // One value per definition. Extras are a merge artefact and are dropped; orphans
        // (definition nil) are kept, since their definition may still be in transit.
        var valuesByFieldID: [UUID: FieldValue] = [:]
        for value in stored {
            guard let fieldID = value.fieldDefinition?.fieldID else { continue }
            if valuesByFieldID[fieldID] == nil {
                valuesByFieldID[fieldID] = value
            } else {
                context.delete(value)
                changed = true
            }
        }

        var result: [FieldValue] = []
        for draft in drafts {
            let definition = draft.fieldDefinition
            let value: FieldValue
            if let existing = valuesByFieldID[definition.fieldID] {
                value = existing
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
                // Same insert-then-relate order as the item: the custom-sort count filters on
                // the fieldDefinition FK.
                value = FieldValue(fieldDefinition: nil, fieldType: draft.fieldType)
                context.insert(value)
                value.fieldDefinition = definition
                value.item = item
                // A second draft for the same definition updates this one rather than
                // inserting again.
                valuesByFieldID[definition.fieldID] = value
                changed = true
            }
            if apply(draft, to: value) { changed = true }
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

    /// Sort keys, search blob and facet mirrors. Each is assigned only when it differs, so
    /// an unchanged item stays clean and exports nothing.
    private static func refreshDerivedColumns(
        on item: CatalogueItem,
        fieldValues: [FieldValue],
        definitions: [FieldDefinition]
    ) {
        for value in fieldValues {
            let sortKey = SortKeyEncoder.sortKey(for: value)
            if value.sortKey != sortKey { value.sortKey = sortKey }
        }
        // Tiebreak keys depend on every field's sortKey, so they follow in a second pass.
        for value in fieldValues {
            let tiebreakKey = SortKeyEncoder.tiebreakKey(
                for: value,
                allFieldValuesOnItem: fieldValues,
                fieldDefinitionsByPriority: definitions,
                itemCreatedDate: item.createdDate
            )
            if value.tiebreakKey != tiebreakKey { value.tiebreakKey = tiebreakKey }
        }

        let searchText = SearchTextBuilder.build(from: fieldValues)
        if item.searchText != searchText { item.searchText = searchText }

        let facets = ItemFacetBuilder.facets(from: fieldValues, definitions: definitions)
        if item.statusValue != facets.statusValue { item.statusValue = facets.statusValue }
        if item.flagKeys != facets.flagKeys { item.flagKeys = facets.flagKeys }
    }

    // MARK: - Photos

    private static func applyPhotoDrafts(
        _ drafts: [PhotoDraft],
        to item: CatalogueItem,
        stored: [ItemPhoto],
        context: ModelContext
    ) -> (changed: Bool, coverThumbnailData: Data?) {
        var changed = false
        let existingByID = Dictionary(stored.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: Set<PersistentIdentifier> = []

        for draft in drafts {
            let trimmedCaption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let caption: String? = trimmedCaption.isEmpty ? nil : trimmedCaption

            if let id = draft.existingPhotoID, let photo = existingByID[id] {
                kept.insert(id)
                if photo.priority != draft.priority {
                    photo.priority = draft.priority
                    changed = true
                }
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
                let photo = ItemPhoto(
                    imageData: draft.imageData,
                    thumbnailData: draft.imageData.makeThumbnail(),
                    priority: draft.priority,
                    caption: caption
                )
                context.insert(photo)
                photo.item = item
                changed = true
            }
        }

        for (id, photo) in existingByID where !kept.contains(id) {
            context.delete(photo)
            changed = true
        }

        guard changed else { return (false, nil) }
        let cover = drafts.min { $0.priority < $1.priority }
        return (true, cover?.imageData.makeThumbnail())
    }
}
