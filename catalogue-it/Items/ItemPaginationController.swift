//
//  ItemPaginationController.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 10/04/2026.
//

import SwiftUI
import SwiftData
import CoreData

// MARK: - Item Pagination Controller

/// Offset-based pagination over an `ItemQuery`, which does the sorting and filtering in the store.
///
/// Reacts to `NSManagedObjectContextDidSave`, behind a count guard for date-added sort; a
/// custom sort always rebuilds, since editing the sort field reorders without changing the
/// count. `.remoteChangesMerged` always rebuilds: a remote edit can move an item between tabs
/// without changing the count.
@MainActor
@Observable
final class ItemPaginationController {

    static let pageSize = ItemQuery.defaultPageSize

    private(set) var items: [CatalogueItem] = []
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var totalCount = 0
    /// `totalCount` without the flag filters, which hide items with no other sign on screen.
    private(set) var unflaggedCount = 0
    /// Tells "catalogue is empty" from "search found nothing".
    private(set) var hasAnyItems = false

    private var query: ItemQuery?

    private var currentFingerprint: FilterFingerprint?
    private var currentContext: ModelContext?
    private var observers: [NSObjectProtocol] = []

    // A save or merge arrived while paused behind a push; forces a refresh on the next appear.
    private var pendingStoreChange = false
    private var standbyObservers: [NSObjectProtocol] = []

    isolated deinit {
        // onDisappear doesn't always precede release.
        (observers + standbyObservers).forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

    // MARK: - Public API

    /// Without `force`, an identical fingerprint with items loaded is a no-op, which keeps the
    /// scroll position when navigating back.
    func reset(fingerprint: FilterFingerprint, context: ModelContext, force: Bool = false) {
        if !force, fingerprint == currentFingerprint, !items.isEmpty {
            return
        }

        // Reloads to the depth reached: on iPad the list stays on screen through edits and merges,
        // and dropping to one page would clamp a reader at row 300. A fingerprint change starts
        // from the top.
        let previousDepth = (force && fingerprint == currentFingerprint) ? items.count : 0

        currentFingerprint = fingerprint
        currentContext = context

        items = []
        query = nil
        hasMore = true
        isLoadingMore = false

        do {
            let query = try ItemQuery(fingerprint: fingerprint, context: context)
            totalCount = query.totalCount
            unflaggedCount = (try? Self.countWithoutFlags(fingerprint: fingerprint, context: context, matching: totalCount)) ?? totalCount
            hasAnyItems = query.hasAnyItems
            hasMore = query.hasMore
            self.query = query
        } catch {
            hasMore = false
            return
        }

        loadMore(context: context)
        while items.count < previousDepth, hasMore {
            loadMore(context: context)
        }

        // Pushing the content column in compact width can fire onAppear and onDisappear back to back
        // for a view that stays on screen; left in standby, its first saved item would never show.
        if observers.isEmpty, !standbyObservers.isEmpty {
            pendingStoreChange = false
            startObservingStoreChanges()
        }
    }

    func loadMore(context: ModelContext) {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            if let page = try query?.nextPage(context: context) {
                items += page
            }
        } catch {
        }
        hasMore = query?.hasMore ?? false
    }

    /// Pair with `stopObservingStoreChanges`. Returns `true` when a pending change forced a
    /// reset, so the caller should restore the scroll position.
    @discardableResult
    func startObservingStoreChanges() -> Bool {
        standbyObservers.forEach { NotificationCenter.default.removeObserver($0) }
        standbyObservers = []

        // DidSave fires only on explicit saves, not fetches, so our own fetches can't loop back into
        // a reset. The mirroring context's saves post it too, but a remote edit leaves the count
        // unchanged and slips past the guard; `.remoteChangesMerged` covers that, arriving after
        // RemoteChangeObserver has repaired derived state.
        if observers.isEmpty {
            let saveToken = NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleStoreChange() }
            }
            let remoteToken = NotificationCenter.default.addObserver(
                forName: .remoteChangesMerged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleRemoteChange() }
            }
            observers = [saveToken, remoteToken]
        }

        if pendingStoreChange {
            pendingStoreChange = false
            if let fp = currentFingerprint, let ctx = currentContext {
                reset(fingerprint: fp, context: ctx, force: true)
            }
            return true
        }
        return false
    }

    func stopObservingStoreChanges() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []

        // Standby observers note changes made while behind a push; the refresh waits for the next appear.
        guard standbyObservers.isEmpty else { return }
        standbyObservers = [.NSManagedObjectContextDidSave, .remoteChangesMerged].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.pendingStoreChange = true }
            }
        }
    }

    // MARK: - Reactivity

    /// No count guard: a remote edit can change an item's tab, flags or position without
    /// changing the count.
    private func handleRemoteChange() {
        guard let fp = currentFingerprint, let ctx = currentContext else { return }
        reset(fingerprint: fp, context: ctx, force: true)
    }

    private func handleStoreChange() {
        guard let fp = currentFingerprint, let ctx = currentContext else { return }

        // Editing the sort field's value reorders without changing the count.
        if case .field = ItemSortField(rawValue: fp.sortFieldKey) {
            reset(fingerprint: fp, context: ctx, force: true)
            return
        }

        guard (try? ItemQuery.matchingCount(fingerprint: fp, context: ctx)) == totalCount else {
            reset(fingerprint: fp, context: ctx, force: true)
            return
        }
        // A save the flag filters hide leaves the list as it is but changes what they hide.
        if let unflagged = try? Self.countWithoutFlags(fingerprint: fp, context: ctx, matching: totalCount) {
            unflaggedCount = unflagged
        }
    }

    private static func countWithoutFlags(fingerprint: FilterFingerprint, context: ModelContext, matching: Int) throws -> Int {
        guard !fingerprint.flagTokens.isEmpty else { return matching }
        return try ItemQuery.matchingCount(fingerprint: fingerprint, context: context, ignoreFlags: true)
    }
}
