//
//  DeletionService.swift
//  catalogue-it
//

import Foundation
import SwiftData
import os

/// Deletes by re-fetching rows rather than walking relationships: a relationship can hold a
/// stale or future-backed model (after an undo, rollback or remote delete), and deleting one
/// crashes snapshot creation ("_FullFutureBackingData"). Fetching also catches orphans a walk
/// would miss.
///
/// Not actor-isolated: works on whichever executor owns the context passed in. The `…AndSave`
/// variants are `@MainActor` because they suspend undo registration.
nonisolated enum DeletionService {
    private static let logger = Logger(subsystem: "catalogue-it", category: "DeletionService")

    /// Bottom-up. Doesn't save — the caller saves once per batch.
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

    /// Every fetch joins through at most one relationship: deeper or ORed joins compile to SQL
    /// that intermittently misses or over-matches rows.
    static func deleteCatalogue(_ catalogue: Catalogue, in context: ModelContext) {
        let catalogueID = catalogue.persistentModelID
        do {
            let items = try context.fetch(FetchDescriptor<CatalogueItem>(
                predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID }))
            for item in items { deleteItem(item, in: context) }

            try deleteFieldDefinitionsAndCatalogueRow(catalogueID: catalogueID, in: context)
        } catch {
            logger.error("Catalogue delete fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Once the items are gone. Also called by `BackgroundDeletionActor` after its batches.
    static func deleteFieldDefinitionsAndCatalogueRow(
        catalogueID: PersistentIdentifier,
        in context: ModelContext
    ) throws {
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
    }

    /// Not undoable: the alert promises permanence, and SwiftData's undo of a saved delete
    /// re-inserts under dead identities that vanish on the next save.
    @MainActor
    static func deleteCatalogueAndSave(_ catalogue: Catalogue, in context: ModelContext) {
        context.withUndoRegistrationSuspended {
            deleteCatalogue(catalogue, in: context)
            save(context)
        }
    }

    /// Not undoable either: undoing mid-teardown would resurrect a half-deleted catalogue.
    @MainActor
    static func markForBackgroundDeletion(_ catalogue: Catalogue, in context: ModelContext) {
        context.withUndoRegistrationSuspended {
            catalogue.pendingDeletion = true
            save(context)
        }
        // After saving: the save replaces a temporary ID with the permanent one.
        BackgroundDeletionActor.scheduleDeletion(of: catalogue.persistentModelID)
    }

    @MainActor
    static func deleteItemsAndSave(_ items: [CatalogueItem], in context: ModelContext) {
        context.withUndoRegistrationSuspended {
            for item in items { deleteItem(item, in: context) }
            save(context)
        }
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            // So the failed deletes don't sit poisoned in the context; the fetch-based paths are safe
            // to retry.
            context.rollback()
            logger.error("Delete save failed: \(error.localizedDescription, privacy: .public)")
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
