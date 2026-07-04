//
//  DeletionService.swift
//  catalogue-it
//

import Foundation
import SwiftData
import os

/// Hard-deletes items and catalogues by re-fetching every row from the store rather than
/// walking in-memory relationship arrays. Relationship arrays can contain stale or
/// future-backed models (after an undo, a rollback, or a delete elsewhere), and calling
/// `context.delete()` on one of those crashes SwiftData's snapshot creation
/// ("Unexpected backing data for snapshot creation: _FullFutureBackingData"). Predicate
/// fetches return only live, fully-materialised rows, so deletion succeeds regardless of
/// how the in-memory graph got into its current state — and also sweeps up orphaned rows
/// (e.g. a FieldValue with a definition but no item) that a relationship walk would miss.
@MainActor
enum DeletionService {
    private static let logger = Logger(subsystem: "catalogue-it", category: "DeletionService")

    /// Deletes an item and its children bottom-up. Does NOT save — caller saves once after a batch.
    static func deleteItem(_ item: CatalogueItem, in context: ModelContext) {
        let itemID = item.persistentModelID
        do {
            let photos = try context.fetch(FetchDescriptor<ItemPhoto>(
                predicate: #Predicate { $0.item?.persistentModelID == itemID }))
            for photo in photos { context.delete(photo) }

            let values = try context.fetch(FetchDescriptor<FieldValue>(
                predicate: #Predicate { $0.item?.persistentModelID == itemID }))
            for value in values { context.delete(value) }

            let items = try context.fetch(FetchDescriptor<CatalogueItem>(
                predicate: #Predicate { $0.persistentModelID == itemID }))
            for fetched in items { context.delete(fetched) }
        } catch {
            logger.error("Item delete fetch failed: \(error.localizedDescription, privacy: .public)")
        }
        removeThumbnails(for: [itemID])
    }

    /// Deletes a catalogue and its entire graph bottom-up: each item with its children,
    /// then each field definition with any field values orphaned from their item, then the
    /// catalogue itself. Every fetch joins through at most one relationship — predicates
    /// joining two levels deep (or ORing across two joins) compile to unreliable SQL that
    /// intermittently misses or over-matches rows.
    static func deleteCatalogue(_ catalogue: Catalogue, in context: ModelContext) {
        let catalogueID = catalogue.persistentModelID
        do {
            let items = try context.fetch(FetchDescriptor<CatalogueItem>(
                predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID }))
            for item in items { deleteItem(item, in: context) }

            let definitions = try context.fetch(FetchDescriptor<FieldDefinition>(
                predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID }))
            for definition in definitions {
                let definitionID = definition.persistentModelID
                let orphanValues = try context.fetch(FetchDescriptor<FieldValue>(
                    predicate: #Predicate { $0.fieldDefinition?.persistentModelID == definitionID }))
                for value in orphanValues { context.delete(value) }
                context.delete(definition)
            }

            let catalogues = try context.fetch(FetchDescriptor<Catalogue>(
                predicate: #Predicate { $0.persistentModelID == catalogueID }))
            for fetched in catalogues { context.delete(fetched) }
        } catch {
            logger.error("Catalogue delete fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes a catalogue, saves, and registers an app-level undo action that restores
    /// the catalogue from a value snapshot. SwiftData's own undo registration is suspended
    /// for the delete: natively undoing a saved deletion re-inserts models under their old
    /// (now deleted) row identities, which then silently vanish on the next save — the
    /// data is never actually restored.
    static func deleteCatalogueAndSave(_ catalogue: Catalogue, in context: ModelContext) {
        let snapshotURL = writeUndoSnapshot(of: catalogue, in: context)
        let saved = withSuspendedUndoRegistration(context) {
            deleteCatalogue(catalogue, in: context)
            return save(context)
        }
        guard saved, let snapshotURL, let undoManager = context.undoManager else { return }
        undoManager.registerUndo(withTarget: context) { target in
            MainActor.assumeIsolated {
                restoreCatalogue(from: snapshotURL, in: target)
            }
        }
        undoManager.setActionName(String(localized: "Delete Catalogue"))
    }

    static func deleteItemsAndSave(_ items: [CatalogueItem], in context: ModelContext) {
        // Suspended for the same reason as above: a native undo of this hard delete would
        // silently restore nothing. Recently Deleted is the recovery path for items.
        _ = withSuspendedUndoRegistration(context) {
            for item in items { deleteItem(item, in: context) }
            return save(context)
        }
    }

    @discardableResult
    private static func save(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            // Roll back so the failed deletes don't sit poisoned in the context; the
            // fetch-based delete paths above stay safe to retry after a rollback.
            context.rollback()
            logger.error("Delete save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Runs `body` with SwiftData's automatic undo registration disabled, so hard deletes
    /// never land on the undo stack as natively-undoable (they aren't — see above).
    private static func withSuspendedUndoRegistration<T>(_ context: ModelContext, _ body: () -> T) -> T {
        let undoManager = context.undoManager
        context.undoManager = nil
        defer { context.undoManager = undoManager }
        return body()
    }

    // MARK: - Undo Snapshot & Restore

    /// Serialises the catalogue graph to a `CatalogueDTO` JSON file in the temporary
    /// directory and returns its URL, or nil if the catalogue no longer exists or the
    /// write fails. Written to disk so the undo stack doesn't retain photo data in memory.
    /// Built from fresh fetches (single relationship join per fetch), never from the
    /// possibly-stale in-memory relationship arrays — the same discipline as deletion.
    private static func writeUndoSnapshot(of catalogue: Catalogue, in context: ModelContext) -> URL? {
        let catalogueID = catalogue.persistentModelID
        do {
            guard let fetched = try context.fetch(FetchDescriptor<Catalogue>(
                predicate: #Predicate { $0.persistentModelID == catalogueID })).first else { return nil }

            let definitions = try context.fetch(FetchDescriptor<FieldDefinition>(
                predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID }))

            let items = try context.fetch(FetchDescriptor<CatalogueItem>(
                predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID }))

            var itemDTOs: [CatalogueItemDTO] = []
            for item in items.sorted(by: { $0.createdDate < $1.createdDate }) {
                let itemID = item.persistentModelID
                let values = try context.fetch(FetchDescriptor<FieldValue>(
                    predicate: #Predicate { $0.item?.persistentModelID == itemID }))
                let photos = try context.fetch(FetchDescriptor<ItemPhoto>(
                    predicate: #Predicate { $0.item?.persistentModelID == itemID }))
                itemDTOs.append(CatalogueItemDTO(
                    createdDate: item.createdDate,
                    isWishlist: item.isWishlist,
                    notes: item.notes,
                    deletedDate: item.deletedDate,
                    fieldValues: values.compactMap(FieldValueDTO.init),
                    photos: photos.sorted { $0.priority < $1.priority }.map(ItemPhotoDTO.init)
                ))
            }

            let dto = CatalogueDTO(
                name: fetched.name,
                iconName: fetched.iconName,
                colorHex: fetched.colorHex,
                createdDate: fetched.createdDate,
                priority: fetched.priority,
                sortFieldKey: fetched.sortFieldKey,
                sortDirection: fetched.sortDirection,
                fieldDefinitions: definitions
                    .sorted { $0.priority < $1.priority }
                    .map(FieldDefinitionDTO.init),
                items: itemDTOs
            )

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("catalogue-undo", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            pruneOldSnapshots(in: directory)
            let url = directory.appendingPathComponent("\(UUID().uuidString).json")
            try JSONEncoder().encode(dto).write(to: url)
            return url
        } catch {
            logger.error("Undo snapshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Rebuilds the catalogue graph from a snapshot file. Invoked from the undo action.
    private static func restoreCatalogue(from url: URL, in context: ModelContext) {
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: url)
                let dto = try JSONDecoder().decode(CatalogueDTO.self, from: data)
                _ = await dto.makeCatalogue(in: context, priorityOffset: 0)
                try context.save()
            } catch {
                logger.error("Catalogue restore failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Snapshot files are only reachable while their undo action is on this session's
    /// stack; anything older than a day is unreachable garbage.
    private static func pruneOldSnapshots(in directory: URL) {
        let cutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func removeThumbnails(for itemIDs: [PersistentIdentifier]) {
        Task.detached {
            for itemID in itemIDs {
                if let url = ThumbnailLoader.thumbnailCacheURL(for: itemID) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }
}
