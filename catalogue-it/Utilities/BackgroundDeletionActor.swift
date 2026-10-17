//
//  BackgroundDeletionActor.swift
//  catalogue-it
//

import Foundation
import SwiftData
import os

/// The main context flags `pendingDeletion` and saves, hiding the catalogue at once; this actor
/// deletes the graph in batches on its own context. The flag survives a crash, and
/// `resumePendingDeletions()` finishes at launch, including deletions synced from elsewhere.
/// The `DeletionService` pitfalls apply here too.
@ModelActor
actor BackgroundDeletionActor {
    private static let logger = Logger(subsystem: "catalogue-it", category: "BackgroundDeletionActor")

    /// Bounds peak memory (each item can carry photos as `Data`) and keeps merges small.
    private static let batchSize = 200

    // MARK: - Scheduling

    @MainActor static var container: ModelContainer?
    @MainActor private static var shared: BackgroundDeletionActor?

    /// Shared, so concurrent requests serialise rather than race on separate contexts.
    @MainActor private static func sharedActor() -> BackgroundDeletionActor? {
        if let shared { return shared }
        guard let container else {
            logger.error("BackgroundDeletionActor.container was never configured")
            return nil
        }
        let actor = BackgroundDeletionActor(modelContainer: container)
        shared = actor
        return actor
    }

    /// `Task.detached`, not `Task`: a ModelActor runs jobs on the *calling* task's thread, so a
    /// plain `Task` would inherit the main actor and freeze the UI. Asserted in `deleteCatalogue`.
    @MainActor static func scheduleDeletion(of catalogueID: PersistentIdentifier) {
        guard let actor = sharedActor() else { return }
        Task.detached(priority: .utility) {
            await actor.deleteCatalogue(id: catalogueID)
        }
    }

    /// Call once at launch. Detached for the same reason as `scheduleDeletion`.
    @MainActor static func resumePendingDeletions() {
        guard let actor = sharedActor() else { return }
        Task.detached(priority: .utility) {
            await actor.deleteAllPendingCatalogues()
        }
    }

    // MARK: - Teardown (background)

    func deleteAllPendingCatalogues() {
        do {
            let pending = try modelContext.fetch(FetchDescriptor<Catalogue>(
                predicate: #Predicate { $0.pendingDeletion }))
            for catalogue in pending {
                deleteCatalogue(id: catalogue.persistentModelID)
            }
        } catch {
            Self.logger.error("Pending-deletion fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteCatalogue(id catalogueID: PersistentIdentifier) {
        assert(!Thread.isMainThread,
               "Catalogue teardown ran on the main thread — a ModelActor executes on the calling task's thread, so this must be entered via Task.detached")
        do {
            while true {
                var descriptor = FetchDescriptor<CatalogueItem>(
                    predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID })
                descriptor.fetchLimit = Self.batchSize
                let items = try modelContext.fetch(descriptor)
                if items.isEmpty { break }
                for item in items {
                    DeletionService.deleteItem(item, in: modelContext)
                }
                try modelContext.save()
            }

            try DeletionService.deleteFieldDefinitionsAndCatalogueRow(
                catalogueID: catalogueID, in: modelContext)
            try modelContext.save()
        } catch {
            // The flag stays set, so the launch sweep retries.
            modelContext.rollback()
            Self.logger.error("Background catalogue delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
