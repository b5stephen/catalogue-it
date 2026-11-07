//
//  ItemSelectionState.swift
//  catalogue-it
//

import SwiftUI
import SwiftData

// MARK: - Item Selection State

/// Select mode for one catalogue's item list: whether it is on, what is picked, and the
/// background work Share and Delete start from it.
@MainActor
@Observable
final class ItemSelectionState {
    private(set) var isSelecting = false
    private(set) var selection = ItemSelection.none

    /// Rows done and the total while background work runs; `nil` when idle.
    private(set) var progress: (done: Int, total: Int)?
    /// Set only if the work is still running after ~500ms, so quick work never flashes the overlay.
    private(set) var showsProgress = false

    var isWorking: Bool { progress != nil }

    // MARK: Selecting

    func begin() { isSelecting = true }

    func end() {
        isSelecting = false
        selection = .none
    }

    func isSelected(_ item: CatalogueItem) -> Bool {
        selection.contains(item.persistentModelID)
    }

    func toggle(_ item: CatalogueItem) {
        selection = selection.toggled(item.persistentModelID)
    }

    func selectAll(_ fingerprint: FilterFingerprint) {
        selection = .matching(fingerprint, excluding: [])
    }

    func deselectAll() { selection = .none }

    func follow(_ fingerprint: FilterFingerprint) {
        let following = selection.following(fingerprint)
        if following != selection { selection = following }
    }

    func count(totalMatching: Int) -> Int {
        selection.count(totalMatching: totalMatching)
    }

    // MARK: Background work

    /// `chosen` defaults to the user's picks.
    func resolve(
        _ chosen: ItemSelection? = nil,
        container: ModelContainer,
        current: FilterFingerprint
    ) async -> [PersistentIdentifier] {
        let selection = chosen ?? selection
        return await run { _ in
            try await selection.resolve(in: container, current: current)
        } ?? []
    }

    /// The composer's input for `chosen` (default: the picks), `nil` if it comes to no items. The
    /// IDs are resolved off the main thread; only the first few items are loaded.
    func prepareExport(
        _ chosen: ItemSelection? = nil,
        format: ExportFormat? = nil,
        filters: ExportFilters? = nil,
        container: ModelContainer,
        context: ModelContext,
        current: FilterFingerprint
    ) async -> ExportRequest? {
        let ids = await resolve(chosen, container: container, current: current)
        guard !ids.isEmpty else { return nil }
        return ExportRequest(
            export: ExportItems(ids: ids, in: context),
            format: format ?? .defaultFormat(forItemCount: ids.count),
            filters: filters
        )
    }

    func softDelete(_ ids: [PersistentIdentifier], container: ModelContainer) async -> Bool {
        await setDeletedDate(.now, for: ids, container: container)
    }

    func restore(_ ids: [PersistentIdentifier], container: ModelContainer) async {
        _ = await setDeletedDate(nil, for: ids, container: container)
    }

    private func setDeletedDate(_ date: Date?, for ids: [PersistentIdentifier], container: ModelContainer) async -> Bool {
        await run { progress -> Void in
            let task = Task.detached(priority: .userInitiated) {
                try await ItemTrashActor(modelContainer: container).setDeletedDate(date, for: ids, onProgress: progress)
            }
            try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } != nil
    }

    /// Runs `work`, showing progress if it takes a while. `nil` if it failed.
    private func run<Result: Sendable>(
        _ work: @escaping @Sendable (@escaping @Sendable (Int, Int) -> Void) async throws -> Result
    ) async -> Result? {
        guard progress == nil else { return nil }
        progress = (done: 0, total: 0)
        let overlayDelay = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { showsProgress = true }
        }
        let (updates, continuation) = AsyncStream.makeStream(of: (Int, Int).self, bufferingPolicy: .bufferingNewest(1))
        let watcher = Task {
            for await (done, total) in updates { progress = (done: done, total: total) }
        }
        defer {
            continuation.finish()
            watcher.cancel()
            overlayDelay.cancel()
            showsProgress = false
            progress = nil
        }
        return try? await work { done, total in continuation.yield((done, total)) }
    }
}
