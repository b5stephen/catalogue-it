//
//  RemoteChangeObserver.swift
//  catalogue-it
//

import CoreData
import Foundation
import SwiftData
import os

// MARK: - Notification

extension Notification.Name {
    /// Posted on the main queue once `RemoteChangeObserver` has finished a pass, i.e. after
    /// the merged rows are on disk *and* the derived state that depends on them (facet
    /// mirrors, thumbnail caches) has been brought back in step. `ItemPaginationController`
    /// reloads on this without its count guard, since an edit merged from another device
    /// changes no count. Expect it after local saves too: once an export completes, the
    /// mirroring context writes CloudKit system fields back into the store, and that write
    /// is a remote change as far as the coordinator is concerned.
    static let remoteChangesMerged = Notification.Name("catalogue-it.remoteChangesMerged")
}

// MARK: - Remote Change Observer

/// Reacts to changes merged into the store by CloudKit sync.
///
/// Local writes go through code that keeps derived state in step — facet mirrors, thumbnail
/// caches, background deletion. A change arriving from another device bypasses all of it: the
/// row simply appears in the store. This observer is the equivalent hook for that path.
///
/// `NSPersistentStoreRemoteChange` fires once per merged batch, so a first sync of a large
/// catalogue posts it repeatedly; everything here is debounced into a single pass.
@MainActor
enum RemoteChangeObserver {
    private static let logger = Logger(subsystem: "catalogue-it", category: "RemoteChangeObserver")

    /// Long enough to collapse a burst of merges into one pass, short enough that the UI
    /// corrects itself while the user is still looking at it.
    private static let debounce = Duration.seconds(1.5)

    private static var container: ModelContainer?
    private static var observer: NSObjectProtocol?
    private static var pendingWork: Task<Void, Never>?

    /// The last history transaction examined. `nil` until the first pass, which reads from
    /// launch instead: anything merged while the app was not running is imported again
    /// after launch, so it lands after that point.
    private static var lastHistoryToken: DefaultHistoryToken?
    private static var launchDate = Date.now

    /// Stamped on the main context so its own transactions can be told apart from the
    /// mirroring's in persistent history.
    static let mainContextAuthor = "catalogue-it.main"

    /// Fingerprint of each catalogue's field configuration as of the last pass. Facet mirrors
    /// are only rebuilt for catalogues whose fingerprint actually moved — a full rebuild walks
    /// every item, and catalogues can hold 2000+.
    private static var fieldFingerprints: [PersistentIdentifier: String] = [:]

    // MARK: - Lifecycle

    /// Call once at app startup, after `container` is built.
    static func start(container: ModelContainer) {
        guard observer == nil else { return }
        self.container = container
        container.mainContext.author = mainContextAuthor
        launchDate = .now
        seedFingerprints()

        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { _ in
            Task { @MainActor in schedulePass() }
        }
    }

    // MARK: - Debounce

    private static func schedulePass() {
        pendingWork?.cancel()
        pendingWork = Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await runPass()
        }
    }

    private static func runPass() async {
        guard let container else { return }

        // Deletions flagged on another device. `resumePendingDeletions` is otherwise only
        // called at launch, so without this a catalogue deleted elsewhere stays on disk
        // (hidden from the UI) for the rest of the session.
        BackgroundDeletionActor.resumePendingDeletions()

        // A photo replaced on another device arrives under the same local identifier, so both
        // thumbnail caches would keep serving the old image with nothing to invalidate them.
        // Clearing wholesale rather than diffing is deliberate: regeneration is lazy and
        // per-row (see ItemRowView/ItemCardView), so only the handful of rows actually on
        // screen pay for it, and thumbnails are always regenerable from the source photos.
        // Rows have landed; let the sync indicator's count catch up.
        CloudKitSyncMonitor.shared.refreshCount()

        await ImageCache.shared.removeAll()
        ThumbnailLoader.clearDiskCache()
        // Mounted rows still hold their decoded image; this is what makes them look again.
        ThumbnailCacheState.shared.invalidateAll()

        await recomputeFacetsForChangedCatalogues(in: container.mainContext)
        await recomputeDerivedColumnsForMergedValues(in: container.mainContext)

        // Last, so a listener that reloads sees the corrected derived columns.
        NotificationCenter.default.post(name: .remoteChangesMerged, object: nil)
    }

    // MARK: - Derived columns of merged items

    /// A field value edited on another device arrives on its own: CloudKit merges per record,
    /// so the `FieldValue` row is right but everything derived from the item's full set of
    /// values — the search blob, the facet mirrors, and the tiebreak key on every sibling —
    /// was computed on that device from *its* view of the item, which may not have had this
    /// device's edits yet. Recomputing here brings them back in step.
    ///
    /// The write this makes is itself exported, which is safe only because the recompute is
    /// deterministic and compare-before-assign (see `ItemDerivedColumns`): the other device
    /// imports it, recomputes, gets the same values and writes nothing. To keep even that
    /// round trip from being a trigger, only merged **field content** counts — a merged
    /// `CatalogueItem` row, or a `FieldValue` whose only changed attributes are derived ones,
    /// starts nothing.
    ///
    /// Which rows merged comes from SwiftData history: the transactions since the last pass
    /// not authored by the main context (the only context that writes field values; the
    /// others only delete, which is ignored here). Undo registration is off for the write —
    /// this is upkeep, not the user's edit — and `modifiedDate` is never touched.
    private static func recomputeDerivedColumnsForMergedValues(in context: ModelContext) async {
        let mergedValueIDs: Set<PersistentIdentifier>
        do {
            mergedValueIDs = try mergedFieldContent(in: context)
        } catch {
            logger.error("History fetch failed: \(error, privacy: .public)")
            return
        }
        guard !mergedValueIDs.isEmpty else { return }

        // The item behind each value; skip anything on its way out.
        var items: [PersistentIdentifier: CatalogueItem] = [:]
        for id in mergedValueIDs {
            guard let value = context.model(for: id) as? FieldValue,
                  let item = value.item, item.deletedDate == nil,
                  let catalogue = item.catalogue, !catalogue.pendingDeletion
            else { continue }
            items[item.persistentModelID] = item
        }
        logger.notice("Recomputing derived columns for \(items.count, privacy: .public) items with merged field values")

        await context.withUndoRegistrationSuspended {
            var definitionsByCatalogue: [PersistentIdentifier: [FieldDefinition]] = [:]
            for (index, item) in items.values.enumerated() {
                guard let catalogue = item.catalogue else { continue }
                let definitions = definitionsByCatalogue[catalogue.persistentModelID] ?? {
                    let sorted = catalogue.sortedFieldDefinitions
                    definitionsByCatalogue[catalogue.persistentModelID] = sorted
                    return sorted
                }()
                ItemDerivedColumns.refresh(on: item, fieldValues: item.fieldValues, definitions: definitions)
                if index % 20 == 19 { await Task.yield() }
            }
            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch {
                // Leaving the changes pending would make the user's next save fail too.
                context.rollback()
                logger.error("Derived-column recompute failed to save: \(error, privacy: .public)")
            }
        }
    }

    /// `FieldValue` attributes that are content; a change to any of these is an edit, a
    /// change to the rest is another device's recompute. `item` and `fieldDefinition` are
    /// included because a value can arrive before its parent and be related in a later pass.
    private static let fieldContentAttributes: Set<PartialKeyPath<FieldValue>> = [
        \.fieldType, \.textValue, \.numberValue, \.dateValue, \.boolValue, \.item, \.fieldDefinition,
    ]

    /// Identifiers of every `FieldValue` inserted or content-updated by someone other than
    /// the main context since the last pass, advancing the token.
    private static func mergedFieldContent(in context: ModelContext) throws -> Set<PersistentIdentifier> {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token = lastHistoryToken {
            descriptor.predicate = #Predicate { $0.token > token }
        } else {
            let since = launchDate
            descriptor.predicate = #Predicate { $0.timestamp > since }
        }
        let transactions = try context.fetchHistory(descriptor)
        guard let newest = transactions.last else { return [] }
        lastHistoryToken = newest.token

        var ids: Set<PersistentIdentifier> = []
        for transaction in transactions where transaction.author != mainContextAuthor {
            for change in transaction.changes {
                switch change {
                case .insert(let insert as DefaultHistoryInsert<FieldValue>):
                    ids.insert(insert.changedPersistentIdentifier)
                case .update(let update as DefaultHistoryUpdate<FieldValue>):
                    if update.updatedAttributes.contains(where: fieldContentAttributes.contains) {
                        ids.insert(update.changedPersistentIdentifier)
                    }
                default:
                    continue
                }
            }
        }
        return ids
    }

    // MARK: - Facet mirrors

    /// `CatalogueItem.statusValue` / `.flagKeys` mirror field values *interpreted through the
    /// field's configuration*, so a `FieldDefinition` edited on another device invalidates
    /// them even though no item changed — items would filter into the wrong tab. Only
    /// catalogues whose field configuration actually moved are swept.
    private static func recomputeFacetsForChangedCatalogues(in context: ModelContext) async {
        let catalogues = (try? context.fetch(FetchDescriptor<Catalogue>(
            predicate: #Predicate { !$0.pendingDeletion }))) ?? []

        for catalogue in catalogues {
            let fingerprint = fingerprint(for: catalogue)
            let id = catalogue.persistentModelID
            guard fieldFingerprints[id] != fingerprint else { continue }
            fieldFingerprints[id] = fingerprint
            await CatalogueSortKeyMaintenance.recomputeFacets(for: catalogue, in: context)
        }
    }

    /// Seeds the fingerprint cache at launch so the first remote change doesn't rebuild every
    /// catalogue just because nothing was recorded yet.
    private static func seedFingerprints() {
        guard let context = container?.mainContext else { return }
        let catalogues = (try? context.fetch(FetchDescriptor<Catalogue>())) ?? []
        for catalogue in catalogues {
            fieldFingerprints[catalogue.persistentModelID] = fingerprint(for: catalogue)
        }
    }

    /// Everything a facet mirror is derived from: which fields carry a display role, and the
    /// option set each one is interpreted against.
    private static func fingerprint(for catalogue: Catalogue) -> String {
        catalogue.sortedFieldDefinitions
            .map { definition in
                let options = definition.optionListOptions?.options.joined(separator: ",") ?? ""
                return "\(definition.fieldID)|\(definition.displayRole.rawValue)|\(options)"
            }
            .joined(separator: "\n")
    }
}
