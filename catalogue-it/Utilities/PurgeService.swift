//
//  PurgeService.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Purge Service

enum PurgeService {
    static let retentionDays = 20

    /// Main actor: works on the main context.
    @MainActor
    static func purgeExpiredItems(for catalogue: Catalogue, in context: ModelContext) {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date.now
        ) else { return }

        // Only the expired rows, via the [catalogue, deletedDate, createdDate] index; usually none,
        // and then nothing is saved.
        let catalogueID = catalogue.persistentModelID
        // #Predicate can't resolve static properties like Date.distantFuture.
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
