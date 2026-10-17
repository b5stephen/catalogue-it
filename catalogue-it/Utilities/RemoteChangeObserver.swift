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
    /// After a pass, once merged rows *and* their derived state are in step. Also follows local
    /// saves: after an export the mirroring context writes CloudKit system fields back, which
    /// the coordinator reports as a remote change.
    static let remoteChangesMerged = Notification.Name("catalogue-it.remoteChangesMerged")
}

// MARK: - Remote Change Observer

/// Local writes keep derived state in step; a change merged from another device bypasses all
/// of that, and this is its hook. `NSPersistentStoreRemoteChange` fires per merged batch, so
/// passes are debounced.
@MainActor
enum RemoteChangeObserver {
    private static let logger = Logger(subsystem: "catalogue-it", category: "RemoteChangeObserver")

    private static let debounce = Duration.seconds(1.5)

    private static var container: ModelContainer?
    private static var observer: NSObjectProtocol?
    private static var pendingWork: Task<Void, Never>?

    /// `nil` until the first pass, which reads from launch: anything merged while the app wasn't
    /// running is imported again after launch.
    private static var lastHistoryToken: NSPersistentHistoryToken?
    private static var launchDate = Date.now

    /// From the remote-change notification's `object`: the only handle SwiftData gives on the
    /// Core Data stack, and what history is read through (never `ModelContext.fetchHistory` —
    /// see `PersistentHistoryReader`).
    private static var coordinator: NSPersistentStoreCoordinator?
    private static var loggedMissingCoordinator = false

    /// Stamped on the main context to tell its transactions from the mirroring's.
    static let mainContextAuthor = "catalogue-it.main"

    /// Facet mirrors are rebuilt only for catalogues whose fingerprint moved: a rebuild walks
    /// every item.
    private static var fieldFingerprints: [PersistentIdentifier: String] = [:]

    // MARK: - Lifecycle

    /// Call once at startup, after `container` is built.
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
        ) { notification in
            // Not Sendable; only touched on the main actor.
            nonisolated(unsafe) let object = notification.object
            Task { @MainActor in
                if let coordinator = object as? NSPersistentStoreCoordinator {
                    self.coordinator = coordinator
                }
                schedulePass()
            }
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

        // Otherwise only resumed at launch, so a catalogue deleted elsewhere would stay on disk for
        // the session.
        BackgroundDeletionActor.resumePendingDeletions()

        // A photo replaced elsewhere arrives under the same local identifier, so both caches would
        // keep the old image. Cleared wholesale: regeneration is lazy and per visible row.
        CloudKitSyncMonitor.shared.refreshCount()

        await ImageCache.shared.removeAll()
        ThumbnailLoader.clearDiskCache()
        // Mounted rows still hold their decoded image; this makes them look again.
        ThumbnailCacheState.shared.invalidateAll()

        await recomputeFacetsForChangedCatalogues(in: container.mainContext)
        await recomputeDerivedColumnsForMergedValues(in: container.mainContext)

        // Last, so a listener that reloads sees the corrected derived columns.
        NotificationCenter.default.post(name: .remoteChangesMerged, object: nil)
    }

    // MARK: - Derived columns of merged items

    /// A field value edited elsewhere arrives alone, so everything derived from the item's whole
    /// set of values (search text, facets, sibling tiebreak keys) is stale here.
    ///
    /// The recompute is exported too, which is safe only because it is deterministic and
    /// compare-before-assign (`ItemDerivedColumns`). Only merged field *content* triggers it, not
    /// a merged item row or derived-only change. Merged rows come from persistent history:
    /// transactions not authored by the main context, the only one that writes field values.
    /// Undo registration is off and `modifiedDate` is never touched.
    private static func recomputeDerivedColumnsForMergedValues(in context: ModelContext) async {
        let itemDates: Set<Date>
        do {
            itemDates = try mergedFieldContent()
        } catch {
            logger.error("History fetch failed: \(error, privacy: .public)")
            return
        }
        guard !itemDates.isEmpty else { return }

        let dates = Array(itemDates)
        let candidates = (try? context.fetch(FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { dates.contains($0.createdDate) && $0.deletedDate == nil }))) ?? []
        var items: [PersistentIdentifier: CatalogueItem] = [:]
        for item in candidates {
            guard let catalogue = item.catalogue, !catalogue.pendingDeletion else { continue }
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
                // Pending changes would make the user's next save fail too.
                context.rollback()
                logger.error("Derived-column recompute failed to save: \(error, privacy: .public)")
            }
        }
    }

    /// `createdDate` of every item whose `FieldValue`s another context inserted or changed since the
    /// last pass. Empty until a notification has handed over the coordinator.
    private static func mergedFieldContent() throws -> Set<Date> {
        guard let coordinator else {
            if !loggedMissingCoordinator {
                loggedMissingCoordinator = true
                logger.notice("Remote-change pass ran before any notification carried the coordinator; history not read")
            }
            return []
        }
        let start: PersistentHistoryReader.Start = lastHistoryToken.map { .token($0) } ?? .date(launchDate)
        let merged = try PersistentHistoryReader.mergedFieldContent(
            coordinator: coordinator, since: start, excludingAuthor: mainContextAuthor)
        // Advances on a read, not a recompute: a failed save doesn't revisit these.
        if let newest = merged.newestToken { lastHistoryToken = newest }
        return merged.itemCreatedDates
    }

    // MARK: - Facet mirrors

    /// The mirrors interpret values through field configuration, so a `FieldDefinition` edited
    /// elsewhere invalidates them though no item changed.
    private static func recomputeFacetsForChangedCatalogues(in context: ModelContext) async {
        let catalogues = (try? context.fetch(FetchDescriptor<Catalogue>(
            predicate: #Predicate { !$0.pendingDeletion }))) ?? []

        for catalogue in catalogues {
            let fingerprint = fingerprint(for: catalogue)
            let id = catalogue.persistentModelID
            guard fieldFingerprints[id] != fingerprint else { continue }
            fieldFingerprints[id] = fingerprint
            await context.withUndoRegistrationSuspended {
                await CatalogueSortKeyMaintenance.recomputeFacets(for: catalogue, in: context)
            }
        }
    }

    /// So the first remote change doesn't rebuild every catalogue.
    private static func seedFingerprints() {
        guard let context = container?.mainContext else { return }
        let catalogues = (try? context.fetch(FetchDescriptor<Catalogue>())) ?? []
        for catalogue in catalogues {
            fieldFingerprints[catalogue.persistentModelID] = fingerprint(for: catalogue)
        }
    }

    /// Which fields carry a display role, and the option set each is read against.
    private static func fingerprint(for catalogue: Catalogue) -> String {
        catalogue.sortedFieldDefinitions
            .map { definition in
                let options = definition.optionListOptions?.options.joined(separator: ",") ?? ""
                return "\(definition.fieldID)|\(definition.displayRole.rawValue)|\(options)"
            }
            .joined(separator: "\n")
    }
}
