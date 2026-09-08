//
//  RemoteChangeObserver.swift
//  catalogue-it
//

import CoreData
import Foundation
import SwiftData
import os

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

    /// Fingerprint of each catalogue's field configuration as of the last pass. Facet mirrors
    /// are only rebuilt for catalogues whose fingerprint actually moved — a full rebuild walks
    /// every item, and catalogues can hold 2000+.
    private static var fieldFingerprints: [PersistentIdentifier: String] = [:]

    // MARK: - Lifecycle

    /// Call once at app startup, after `container` is built.
    static func start(container: ModelContainer) {
        guard observer == nil else { return }
        self.container = container
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

        await recomputeFacetsForChangedCatalogues(in: container.mainContext)
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
        catalogue.fieldDefinitions
            .sorted { $0.priority < $1.priority }
            .map { definition in
                let options = definition.optionListOptions?.options.joined(separator: ",") ?? ""
                return "\(definition.fieldID)|\(definition.displayRole.rawValue)|\(options)"
            }
            .joined(separator: "\n")
    }
}
