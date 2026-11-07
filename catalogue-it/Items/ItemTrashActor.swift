//
//  ItemTrashActor.swift
//  catalogue-it
//

import Foundation
import SwiftData

/// Moves items into and out of Recently Deleted on its own context, in batches. A ModelActor
/// runs on the calling task's thread, so enter it with `Task.detached`.
@ModelActor
actor ItemTrashActor {
    private static let batchSize = 200

    typealias Progress = @Sendable (_ done: Int, _ total: Int) -> Void

    /// `nil` restores. Saved per batch; an ID that has gone (purged meanwhile) is skipped.
    func setDeletedDate(_ date: Date?, for ids: [PersistentIdentifier], onProgress: Progress = { _, _ in }) throws {
        onProgress(0, ids.count)
        for start in stride(from: 0, to: ids.count, by: Self.batchSize) {
            try Task.checkCancellation()
            let batch = Array(ids[start..<min(start + Self.batchSize, ids.count)])
            let items = try modelContext.fetch(FetchDescriptor<CatalogueItem>(
                predicate: #Predicate { batch.contains($0.persistentModelID) }))
            for item in items { item.deletedDate = date }
            try modelContext.save()
            onProgress(start + batch.count, ids.count)
        }
    }
}
