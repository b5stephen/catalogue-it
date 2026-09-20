//
//  PersistentHistoryReader.swift
//  catalogue-it
//

@preconcurrency import CoreData
import Foundation

// MARK: - Persistent History Reader

/// Reads the store's persistent history through Core Data rather than
/// `ModelContext.fetchHistory`.
///
/// ⚠️ `ModelContext.fetchHistory` must not be called anywhere in this app. On iOS 26.5 and 27.0
/// a single call — on the main context or a throwaway one, with any descriptor, without even
/// iterating the result — leaves the container unable to encode composite attributes: from
/// the *second* save afterwards, every `Codable` struct/enum column (`FieldDefinition.fieldOptions`,
/// `Catalogue.layoutOptions`) on a dirty row is written as NULL. That is what wiped option
/// lists, Yes/No labels and flag icons in the field (Sept 2026), and it survives
/// compare-before-assign because a save rewrites every composite of a dirty row, not just the
/// ones assigned. `FieldOptionsPersistenceTests.compositesSurviveSavesAfterACoreDataHistoryFetch`
/// pins the Core Data path down as safe.
///
/// The coordinator comes from the `NSPersistentStoreRemoteChange` notification, whose `object`
/// is the `NSPersistentStoreCoordinator` behind the SwiftData store. History tracking is on,
/// since SwiftData enables it for every store.
nonisolated enum PersistentHistoryReader {
    /// Where to read from: the token of the last transaction already examined, or every
    /// transaction since a date when there is none yet.
    enum Start {
        case token(NSPersistentHistoryToken)
        case date(Date)
    }

    /// What one read produced: the `createdDate` of every item that received merged field
    /// content, and the newest token seen so the next read continues from there.
    struct MergedFieldContent {
        var itemCreatedDates: Set<Date> = []
        var newestToken: NSPersistentHistoryToken?
    }

    /// `FieldValue` attributes that are content; a change to any of these is an edit, a
    /// change to the rest is another device's recompute. `item` and `fieldDefinition` are
    /// included because a value can arrive before its parent and be related in a later pass.
    static let fieldContentAttributes: Set<String> = [
        "fieldType", "textValue", "numberValue", "dateValue", "boolValue", "item", "fieldDefinition",
    ]

    /// Every `FieldValue` inserted or content-updated by someone other than `mainAuthor`
    /// since `start`, reported as the `createdDate` of the item each one belongs to.
    ///
    /// Items are identified by `createdDate` because Core Data object IDs cannot be turned
    /// into SwiftData `PersistentIdentifier`s through public API. `createdDate` is set once,
    /// at sub-microsecond precision, and both stacks read the same column, so it is as good
    /// as a key here — and the recompute it feeds is idempotent, so a coincidental extra
    /// match costs one no-op refresh. A value whose item has not arrived yet is skipped; the
    /// relationship being set later is itself a content update and is picked up then.
    static func mergedFieldContent(
        coordinator: NSPersistentStoreCoordinator,
        since start: Start,
        excludingAuthor mainAuthor: String
    ) throws -> MergedFieldContent {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        return try context.performAndWait {
            var result = MergedFieldContent()
            // Built here: the request is not Sendable, and the closure is.
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
            // One fetch with the items prefetched, rather than faulting each value and
            // then its item.
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
