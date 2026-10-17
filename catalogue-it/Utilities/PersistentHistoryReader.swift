//
//  PersistentHistoryReader.swift
//  catalogue-it
//

@preconcurrency import CoreData
import Foundation

// MARK: - Persistent History Reader

/// ⚠️ Never call `ModelContext.fetchHistory`. On iOS 26.5 and 27.0 one call — any context, any
/// descriptor, result unused — makes every container in the process write every `Codable`
/// column of a dirty row as NULL from the second save on. That wiped option lists, labels and
/// flag icons in Sept 2026. `FieldOptionsPersistenceTests` pins this Core Data path as safe.
///
/// The coordinator is the `NSPersistentStoreRemoteChange` notification's `object`. SwiftData
/// enables history tracking for every store.
nonisolated enum PersistentHistoryReader {
    /// The last token examined, or a date when there is none yet.
    enum Start {
        case token(NSPersistentHistoryToken)
        case date(Date)
    }

    struct MergedFieldContent {
        var itemCreatedDates: Set<Date> = []
        var newestToken: NSPersistentHistoryToken?
    }

    /// A change to these is an edit; to the rest, another device's recompute. `item` and
    /// `fieldDefinition` count because a value can arrive before its parent.
    static let fieldContentAttributes: Set<String> = [
        "fieldType", "textValue", "numberValue", "dateValue", "boolValue", "item", "fieldDefinition",
    ]

    /// Items are identified by `createdDate`: Core Data object IDs can't become
    /// `PersistentIdentifier`s through public API. It is set once at sub-microsecond precision,
    /// and the recompute is idempotent, so a coincidental match costs a no-op. A value whose item
    /// hasn't arrived is skipped; relating it later is itself a content update.
    static func mergedFieldContent(
        coordinator: NSPersistentStoreCoordinator,
        since start: Start,
        excludingAuthor mainAuthor: String
    ) throws -> MergedFieldContent {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        return try context.performAndWait {
            var result = MergedFieldContent()
            // Built here: the request isn't Sendable, the closure is.
            let request: NSPersistentHistoryChangeRequest
            switch start {
            case .token(let token): request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            case .date(let date): request = NSPersistentHistoryChangeRequest.fetchHistory(after: date)
            }
            request.resultType = .transactionsAndChanges
            guard let history = try context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = history.result as? [NSPersistentHistoryTransaction]
            else { return result }
            result.newestToken = transactions.last?.token

            var valueIDs: [NSManagedObjectID] = []
            for transaction in transactions where transaction.author != mainAuthor {
                for change in transaction.changes ?? [] where change.changedObjectID.entity.name == "FieldValue" {
                    switch change.changeType {
                    case .insert:
                        valueIDs.append(change.changedObjectID)
                    case .update:
                        let updated = Set((change.updatedProperties ?? []).map(\.name))
                        if !updated.isDisjoint(with: fieldContentAttributes) {
                            valueIDs.append(change.changedObjectID)
                        }
                    case .delete:
                        continue
                    @unknown default:
                        continue
                    }
                }
            }

            guard !valueIDs.isEmpty else { return result }
            // One fetch with items prefetched, rather than faulting each value then its item.
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "FieldValue")
            fetch.predicate = NSPredicate(format: "self IN %@", valueIDs)
            fetch.relationshipKeyPathsForPrefetching = ["item"]
            for value in try context.fetch(fetch) {
                guard let item = value.value(forKey: "item") as? NSManagedObject,
                      let createdDate = item.value(forKey: "createdDate") as? Date
                else { continue }
                result.itemCreatedDates.insert(createdDate)
            }
            return result
        }
    }
}
