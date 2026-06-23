//
//  PurgeService.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Purge Service

enum PurgeService {
    static let retentionDays = 20

    /// Hard-deletes all soft-deleted items for the given catalogue whose
    /// `deletedDate` is older than `retentionDays` days. Must be called on
    /// the MainActor since SwiftData's main context is main-actor-bound.
    @MainActor
    static func purgeExpiredItems(for catalogue: Catalogue, in context: ModelContext) {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date.now
        ) else { return }

        // Fetch only the expired rows from the DB — avoids faulting the entire items
        // relationship into memory. Backed by #Index([\.catalogue, \.deletedDate, \.createdDate]).
        // In the common case (nothing expired) this materialises zero rows and skips the save.
        let catalogueID = catalogue.persistentModelID
        // #Predicate can't resolve static properties (Date.distantFuture) — capture as a local.
        let distantFuture = Date.distantFuture
        let descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { item in
                item.catalogue?.persistentModelID == catalogueID
                    && (item.deletedDate ?? distantFuture) < cutoff
            }
        )
        let expired = (try? context.fetch(descriptor)) ?? []
        guard !expired.isEmpty else { return }
        DeletionService.deleteItemsAndSave(expired, in: context)
    }
}
