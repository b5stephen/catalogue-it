//
//  ItemPaginationController.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 10/04/2026.
//

import SwiftUI
import SwiftData
import CoreData

// MARK: - Filter Fingerprint

/// Captures all inputs that determine which items are shown and in what order.
/// Equality change → full reset of pagination state.
struct FilterFingerprint: Equatable {
    let catalogueID: PersistentIdentifier
    let tab: ItemTab
    let searchText: String
    let sortFieldKey: String
    let sortDirection: String
}

// MARK: - Item Pagination Controller

/// Manages offset-based pagination for the catalogue item list.
///
/// Both sort paths (dateAdded and custom field) produce a globally correct sort order:
/// - dateAdded: FetchDescriptor with sortBy + fetchLimit/fetchOffset.
/// - Custom field: sorted PersistentIdentifier index built once at reset, sliced per page.
///
/// Reactivity (replacing @Query): NSManagedObjectContextObjectsDidChange for local saves,
/// NSPersistentStoreRemoteChangeNotification for iCloud sync writes.
@MainActor
@Observable
final class ItemPaginationController {

    static let pageSize = 50

    private(set) var items: [CatalogueItem] = []
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var totalCount = 0
    /// True when the catalogue contains any items ignoring the current search query.
    /// Used to distinguish "catalogue is empty" from "search returned no results".
    private(set) var hasAnyItems = false

    // Custom field sort only: globally sorted item IDs, built once per reset.
    private var sortedIDs: [PersistentIdentifier] = []

    private var currentFingerprint: FilterFingerprint?
    private var currentContext: ModelContext?
    private var observers: [NSObjectProtocol] = []

    // Set by the standby observer when a store save fires while active observing is paused
    // (e.g. during navigation to item detail). Triggers a force refresh on the next appear.
    private var pendingStoreChange = false
    private var standbyObserver: NSObjectProtocol?

    // MARK: - Public API

    /// Clears pagination state, recomputes counts and (for custom sort) the sorted ID index,
    /// then loads the first page. Call this whenever filter or sort inputs change.
    ///
    /// Pass `force: true` when the underlying data has changed (e.g. a store save) so that
    /// an already-loaded list is refreshed. Without `force`, a call with an identical
    /// fingerprint and existing items is a no-op — this preserves the scroll position when
    /// navigating back from a detail view.
    func reset(fingerprint: FilterFingerprint, context: ModelContext, force: Bool = false) {
        // Skip redundant resets caused by the view re-appearing (e.g. navigating back from
        // item detail). The scroll position is preserved because the items array is unchanged.
        if !force, fingerprint == currentFingerprint, !items.isEmpty {
            return
        }

        currentFingerprint = fingerprint
        currentContext = context

        items = []
        sortedIDs = []
        hasMore = true
        isLoadingMore = false

        do {
            let fullPredicate = makePredicate(fingerprint: fingerprint)
            totalCount = try context.fetchCount(FetchDescriptor<CatalogueItem>(predicate: fullPredicate))

            let noSearchPredicate = makePredicate(fingerprint: fingerprint, ignoreSearch: true)
            let anyCount = try context.fetchCount(FetchDescriptor<CatalogueItem>(predicate: noSearchPredicate))
            hasAnyItems = anyCount > 0

            if case .field(let fieldID) = ItemSortField(rawValue: fingerprint.sortFieldKey) {
                try buildSortedIDs(fingerprint: fingerprint, fieldID: fieldID, context: context)
            }
        } catch {
            hasMore = false
            return
        }

        loadMore(context: context)
    }

    /// Appends the next page of items. Called by the scroll sentinel's onAppear.
    func loadMore(context: ModelContext) {
        guard !isLoadingMore, hasMore else { return }
        guard let fp = currentFingerprint else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            if case .field = ItemSortField(rawValue: fp.sortFieldKey) {
                try loadMoreCustomSort(context: context)
            } else {
                try loadMoreDateAdded(fingerprint: fp, context: context)
            }
        } catch {
            // Leave items unchanged; next scroll attempt will retry.
        }
    }

    /// Starts observing store changes. The controller resets automatically when the
    /// local context is saved or iCloud delivers remote changes.
    /// Call on view appear; pair with stopObservingStoreChanges on disappear.
    func startObservingStoreChanges() {
        // Disarm the standby observer that was watching for saves while we were inactive.
        if let standby = standbyObserver {
            NotificationCenter.default.removeObserver(standby)
            standbyObserver = nil
        }

        // NSManagedObjectContextDidSave fires only on explicit context.save() calls —
        // not during read-only fetch operations. This avoids an infinite loop where
        // our own fetch() calls (including relationship prefetching) would fire
        // NSManagedObjectContextObjectsDidChange, triggering another reset().
        // SwiftData merges iCloud changes into the main context and then saves, so
        // this notification covers both local saves and remote sync.
        if observers.isEmpty {
            let token = NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleStoreChange() }
            }
            observers = [token]
        }

        // A save fired while we were paused (e.g. user edited an item in the detail view).
        // Force a full refresh so sort order and search index reflect the latest data.
        if pendingStoreChange {
            pendingStoreChange = false
            if let fp = currentFingerprint, let ctx = currentContext {
                reset(fingerprint: fp, context: ctx, force: true)
            }
        }
    }

    func stopObservingStoreChanges() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []

        // Arm a lightweight standby observer so we notice saves that occur while the view
        // is behind a navigation push (e.g. the user edits an item in detail view).
        // The full refresh is deferred until the view reappears via startObservingStoreChanges.
        guard standbyObserver == nil else { return }
        standbyObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pendingStoreChange = true }
        }
    }

    // MARK: - Reactivity

    private func handleStoreChange() {
        guard let fp = currentFingerprint, let ctx = currentContext else { return }
        reset(fingerprint: fp, context: ctx, force: true)
    }

    // MARK: - Custom Sort Path

    /// Builds the globally sorted PersistentIdentifier list for custom field sort.
    ///
    /// Step 1: Fetch all FieldValues for the sort field ordered by sortKey (uses the
    ///         (fieldDefinition, sortKey) compound index for an efficient indexed scan).
    /// Step 2: Fetch all candidate CatalogueItem IDs matching the full predicate
    ///         (catalogue + tab + search + soft-delete). No relationship prefetch —
    ///         we only need scalars to build the ID set.
    /// Step 3: Walk step 1 in order, keeping only IDs present in the step 2 candidate set.
    ///
    /// The resulting sortedIDs slice drives each loadMore() call. Items without a FieldValue
    /// for the sort field are excluded (consistent with the previous computeDisplayedItems()
    /// behaviour).
    private func buildSortedIDs(fingerprint: FilterFingerprint, fieldID: UUID, context: ModelContext) throws {
        let ascending = (ItemSortDirection(rawValue: fingerprint.sortDirection) ?? .ascending) == .ascending
        let filterAll = fingerprint.tab == .all
        let filterWishlist = fingerprint.tab == .wishlist

        var fvDescriptor = FetchDescriptor<FieldValue>(
            predicate: #Predicate { fv in
                fv.fieldDefinition?.fieldID == fieldID
                    && fv.item?.deletedDate == nil
                    && (filterAll || fv.item?.isWishlist == filterWishlist)
            },
            sortBy: [SortDescriptor(\.sortKey, order: ascending ? .forward : .reverse)]
        )
        // Prefetch item relationship so .item access below doesn't fire N individual faults.
        fvDescriptor.relationshipKeyPathsForPrefetching = [\.item]

        // Fetching candidates registers them in the context's identity map so that
        // model(for:) in loadMoreCustomSort() resolves them cheaply from memory.
        let candidatePredicate = makePredicate(fingerprint: fingerprint)
        let candidates = try context.fetch(FetchDescriptor<CatalogueItem>(predicate: candidatePredicate))
        let candidateIDs = Set(candidates.map(\.persistentModelID))

        let sortedFieldValues = try context.fetch(fvDescriptor)
        sortedIDs = sortedFieldValues
            .compactMap { $0.item?.persistentModelID }
            .filter { candidateIDs.contains($0) }

        hasMore = !sortedIDs.isEmpty
    }

    private func loadMoreCustomSort(context: ModelContext) throws {
        let start = items.count
        let end = min(start + Self.pageSize, sortedIDs.count)
        guard start < end else {
            hasMore = false
            return
        }
        let slice = sortedIDs[start..<end]

        // Candidates were registered during buildSortedIDs(), so model(for:) resolves
        // from the identity map without additional SQL queries.
        // fieldValues lazy-load per cell during rendering — only visible cells (~15)
        // trigger loads in a LazyVGrid/LazyVStack, so no prefetch needed here.
        let page: [CatalogueItem] = slice.compactMap { context.model(for: $0) as? CatalogueItem }
        items.append(contentsOf: page)
        hasMore = end < sortedIDs.count
    }

    // MARK: - Date Added Sort Path

    private func loadMoreDateAdded(fingerprint: FilterFingerprint, context: ModelContext) throws {
        let ascending = (ItemSortDirection(rawValue: fingerprint.sortDirection) ?? .ascending) == .ascending
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: makePredicate(fingerprint: fingerprint))
        descriptor.sortBy = [SortDescriptor(\.createdDate, order: ascending ? .forward : .reverse)]
        descriptor.fetchLimit = Self.pageSize
        descriptor.fetchOffset = items.count
        // Prefetch fieldValues for this page: all fetched items will render soon
        // (user is at or near the top on first page, near bottom on subsequent pages).
        descriptor.relationshipKeyPathsForPrefetching = [\.fieldValues]

        let page = try context.fetch(descriptor)
        items.append(contentsOf: page)
        hasMore = page.count == Self.pageSize
    }

    // MARK: - Predicate Builder

    private func makePredicate(fingerprint: FilterFingerprint, ignoreSearch: Bool = false) -> Predicate<CatalogueItem> {
        let targetID = fingerprint.catalogueID
        let filterAll = fingerprint.tab == .all
        let filterWishlist = fingerprint.tab == .wishlist
        let hasSearch = !fingerprint.searchText.isEmpty && !ignoreSearch
        let lowercasedQuery = fingerprint.searchText.lowercased()

        return #Predicate { item in
            item.catalogue?.persistentModelID == targetID
                && item.deletedDate == nil
                && (filterAll || item.isWishlist == filterWishlist)
                && (!hasSearch || item.searchText.contains(lowercasedQuery))
        }
    }
}
