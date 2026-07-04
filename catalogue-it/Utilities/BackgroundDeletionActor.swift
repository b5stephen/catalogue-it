//
//  BackgroundDeletionActor.swift
//  catalogue-it
//

import Foundation
import SwiftData
import os

/// Tears down catalogues flagged `pendingDeletion` on a background executor, so deleting
/// a large catalogue never blocks the UI. The flow is: the main context sets the flag and
/// saves (instant, hides the catalogue from every query), then this actor deletes the
/// graph in batches on its own context. Each batch save merges back into the main context
/// automatically. If the app dies mid-teardown the flag survives, and
/// `resumePendingDeletions()` finishes the job on next launch — which also sweeps up
/// pending catalogues that arrive via iCloud sync from another device.
///
/// Deletion reuses `DeletionService`'s fetch-based helpers; all the pitfalls documented
/// there (no relationship walks, joins at most one level deep) apply here unchanged.
@ModelActor
actor BackgroundDeletionActor {
    private static let logger = Logger(subsystem: "catalogue-it", category: "BackgroundDeletionActor")

    /// Items deleted per save. Bounds peak memory (each item can carry multiple photos
    /// as raw `Data`) and keeps main-context merges small.
    private static let batchSize = 200

    // MARK: - Scheduling

    /// Set once at app startup, before any deletion can be requested.
    @MainActor static var container: ModelContainer?
    @MainActor private static var shared: BackgroundDeletionActor?

    /// One shared instance so concurrent deletion requests serialise on the actor
    /// instead of racing on separate contexts.
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

    /// Kicks off background teardown of an already-flagged catalogue.
    ///
    /// Must use `Task.detached`, not `Task`: a ModelActor's default executor runs its
    /// jobs on the *calling* task's thread (verified empirically — where the actor was
    /// created makes no difference). A plain `Task` here would inherit the main actor
    /// and the entire teardown would run on the main thread, freezing the UI — the exact
    /// bug this actor exists to fix. The assert in `deleteCatalogue` guards this.
    @MainActor static func scheduleDeletion(of catalogueID: PersistentIdentifier) {
        guard let actor = sharedActor() else { return }
        Task.detached(priority: .utility) {
            await actor.deleteCatalogue(id: catalogueID)
        }
    }

    /// Finishes any deletions interrupted by app termination (or synced in from another
    /// device). Call once at launch. Detached for the same reason as `scheduleDeletion`.
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
            // Items in batches, each batch committed before the next is fetched.
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
            // Roll back the failed batch; the flag stays set, so the launch sweep retries.
            modelContext.rollback()
            Self.logger.error("Background catalogue delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
