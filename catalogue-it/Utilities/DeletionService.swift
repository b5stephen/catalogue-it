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

    /// Hard deletes are deliberately NOT undoable: the confirmation alert promises the
    /// deletion is permanent, and SwiftData's native undo of a saved delete is broken
    /// anyway (it re-inserts models under their old, now-deleted row identities, which
    /// silently vanish on the next save — nothing is actually restored). Registration is
    /// suspended so the undo stack never offers a lying undo.
    static func deleteCatalogueAndSave(_ catalogue: Catalogue, in context: ModelContext) {
        withSuspendedUndoRegistration(context) {
            deleteCatalogue(catalogue, in: context)
            save(context)
        }
    }

    static func deleteItemsAndSave(_ items: [CatalogueItem], in context: ModelContext) {
        withSuspendedUndoRegistration(context) {
            for item in items { deleteItem(item, in: context) }
            save(context)
        }
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            // Roll back so the failed deletes don't sit poisoned in the context; the
            // fetch-based delete paths above stay safe to retry after a rollback.
            context.rollback()
            logger.error("Delete save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Runs `body` with SwiftData's automatic undo registration disabled, so hard deletes
    /// never land on the undo stack as natively-undoable (see above).
    private static func withSuspendedUndoRegistration<T>(_ context: ModelContext, _ body: () -> T) -> T {
        let undoManager = context.undoManager
        context.undoManager = nil
        defer { context.undoManager = undoManager }
        return body()
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
