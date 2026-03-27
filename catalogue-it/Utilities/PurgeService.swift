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

        catalogue.items
            .filter { guard let d = $0.deletedDate else { return false }; return d < cutoff }
            .forEach { context.delete($0) }
    }
}
