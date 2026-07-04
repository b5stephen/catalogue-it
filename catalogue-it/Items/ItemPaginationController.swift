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
/// Both sort paths (dateAdded and custom field) produce a globally correct sort order
/// using DB-side sorting and filtering — no full in-memory scan:
/// - dateAdded: FetchDescriptor with sortBy + fetchLimit/fetchOffset on CatalogueItem.
/// - Custom field: FetchDescriptor with sortBy + fetchLimit/fetchOffset on FieldValue,
///   leveraging the #Index([\.fieldDefinition, \.sortKey]) compound index. Tab filtering
///   is pushed to the DB predicate; search is applied in-memory on each fetched batch
///   (50 rows) to avoid #Predicate macro compiler timeout on complex optional chains.
///
/// Reactivity (replacing @Query): NSManagedObjectContextDidSave fires when the store
/// is modified. For dateAdded sort, a count-based structural-change guard prevents
/// benign saves that don't change the matching item count from triggering unnecessary
/// list rebuilds. Custom-field sort always rebuilds on a store change instead, since an
/// edit to the active sort field's value can reorder the list without changing the count.
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

    // Custom field sort: explicit DB fetch offset and pre-built FieldValue predicate,
    // constructed once per reset.
    private var customSortOffset = 0
    private var customSortPredicate: Predicate<FieldValue>?
    // PersistentIdentifier of the resolved FieldDefinition — used in the predicate so
    // the DB filters on the FK column, hitting the #Index([\.fieldDefinition, \.sortKey]).
    private var customSortFieldDefID: PersistentIdentifier?

    private var currentFingerprint: FilterFingerprint?
    private var currentContext: ModelContext?
    private var observers: [NSObjectProtocol] = []

    // Set by the standby observer when a store save fires while active observing is paused
    // (e.g. during navigation to item detail). Triggers a force refresh on the next appear.
    private var pendingStoreChange = false
    private var standbyObserver: NSObjectProtocol?

    // MARK: - Public API

    /// Clears pagination state, recomputes counts, resolves the sort field (for custom
    /// sorts), then loads the first page. Call this whenever filter or sort inputs change.
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
        customSortOffset = 0
        customSortPredicate = nil
        customSortFieldDefID = nil
        hasMore = true
        isLoadingMore = false

        do {
            if case .field(let fieldID) = ItemSortField(rawValue: fingerprint.sortFieldKey) {
                try setupCustomSort(fingerprint: fingerprint, fieldID: fieldID, context: context)
            } else {
                try setupDateAddedSort(fingerprint: fingerprint, context: context)
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
                try loadMoreCustomSort(fingerprint: fp, context: context)
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
    /// Returns `true` if a pending store change was detected and a force reset was
    /// performed — the caller should restore the scroll position in that case.
    @discardableResult
    func startObservingStoreChanges() -> Bool {
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
            return true
        }
        return false
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

        // Custom-field sort order can change from an edit that adds/removes no items
        // (e.g. editing the value of the active sort field itself) — a count comparison
        // can't detect that, so always rebuild. dateAdded order is stable across edits,
        // so the cheap count-guard below remains safe (and valuable) there.
        if case .field = ItemSortField(rawValue: fp.sortFieldKey) {
            reset(fingerprint: fp, context: ctx, force: true)
            return
        }

        // Guard against benign saves that don't change the matching item count, so a
        // save unrelated to this list doesn't trigger a needless rebuild.
        guard (try? matchingItemCount(fingerprint: fp, context: ctx)) != totalCount else { return }
        reset(fingerprint: fp, context: ctx, force: true)
    }

    /// Counts CatalogueItems matching the full fingerprint predicate (catalogue + tab + search).
    /// Used by handleStoreChange to detect structural changes without rebuilding the list.
    private func matchingItemCount(fingerprint: FilterFingerprint, context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<CatalogueItem>(predicate: makePredicate(fingerprint: fingerprint)))
    }

    // MARK: - Custom Sort Setup

    /// Resolves the FieldDefinition for the active sort field, pre-computes the FieldValue
    /// predicate (tab-filtered, DB-sorted), and initialises totalCount and hasAnyItems.
    ///
    /// The FieldValue predicate uses the #Index([\.fieldDefinition, \.sortKey]) compound
    /// index on FieldValue via the fieldID equality constraint. Search filtering is deferred
    /// to loadMoreCustomSort (in-memory on each 50-row batch) to avoid #Predicate compiler
    /// timeout on optional-chained .contains expressions.
    private func setupCustomSort(fingerprint: FilterFingerprint, fieldID: UUID, context: ModelContext) throws {
        let catalogueID = fingerprint.catalogueID
        var fieldDesc = FetchDescriptor<FieldDefinition>(
            predicate: #Predicate { $0.fieldID == fieldID && $0.catalogue?.persistentModelID == catalogueID }
        )
        fieldDesc.fetchLimit = 1
        guard let resolvedField = try context.fetch(fieldDesc).first else {
            // Sort field no longer exists (e.g. deleted); treat as empty.
            hasMore = false
            hasAnyItems = false
            totalCount = 0
            return
        }

        let fieldDefID = resolvedField.persistentModelID
        customSortFieldDefID = fieldDefID
        customSortPredicate = makeFieldValuePredicate(fieldDefID: fieldDefID, tab: fingerprint.tab)

        // totalCount mirrors the same catalogue/tab/search filter as the dateAdded path,
        // but additionally requires a FieldValue for the sort field — items without one
        // are never surfaced by loadMoreCustomSort's FieldValue-based fetch, so counting
        // them here would show a total the user can never fully scroll to.
        totalCount = try context.fetchCount(FetchDescriptor<CatalogueItem>(
            predicate: makeCustomSortTotalCountPredicate(fingerprint: fingerprint, fieldDefID: fieldDefID)
        ))
        hasMore = totalCount > 0

        if fingerprint.searchText.isEmpty {
            hasAnyItems = totalCount > 0
        } else {
            let noSearchPredicate = makeCustomSortTotalCountPredicate(fingerprint: fingerprint, fieldDefID: fieldDefID, ignoreSearch: true)
            let anyCount = try context.fetchCount(FetchDescriptor<CatalogueItem>(predicate: noSearchPredicate))
            hasAnyItems = anyCount > 0
        }
    }

    private func loadMoreCustomSort(fingerprint: FilterFingerprint, context: ModelContext) throws {
        guard let predicate = customSortPredicate else { hasMore = false; return }

        let ascending = (ItemSortDirection(rawValue: fingerprint.sortDirection) ?? .ascending) == .ascending
        let hasSearch = !fingerprint.searchText.isEmpty
        let lowercasedQuery = fingerprint.searchText.lowercased()

        // Keep fetching DB pages until at least one item is appended or the FieldValue
        // stream is exhausted. A single page can match zero search results while more
        // matches exist further down; without the loop that would append nothing yet
        // leave hasMore true, and the scroll sentinel (which only re-fires onLoadMore
        // when the list grows) would stall forever.
        let countBeforeLoad = items.count
        repeat {
            var desc = FetchDescriptor<FieldValue>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.sortKey, order: ascending ? .forward : .reverse)]
            )
            desc.fetchLimit = Self.pageSize
            // customSortOffset tracks DB rows fetched so the offset stays correct even
            // when the in-memory search filter drops some rows from the appended items.
            desc.fetchOffset = customSortOffset
            desc.relationshipKeyPathsForPrefetching = [\.item]

            let fieldValues = try context.fetch(desc)
            customSortOffset += fieldValues.count

            // Access item.fieldValues on each result before appending. Items reached via
            // relationship traversal (fv.item) may not have their fieldValues fault resolved
            // yet; touching the property here forces the load before SwiftUI renders the row,
            // preventing "Untitled Item" placeholders for items whose name field is present
            // in the store but appears empty until the fault fires.
            if hasSearch {
                items += fieldValues.compactMap { fv in
                    guard let item = fv.item, item.searchText.contains(lowercasedQuery) else { return nil }
                    _ = item.fieldValues
                    return item
                }
            } else {
                items += fieldValues.compactMap { fv in
                    guard let item = fv.item else { return nil }
                    _ = item.fieldValues
                    return item
                }
            }

            hasMore = fieldValues.count == Self.pageSize
        } while hasMore && items.count == countBeforeLoad
    }

    // MARK: - Date Added Sort Setup

    private func setupDateAddedSort(fingerprint: FilterFingerprint, context: ModelContext) throws {
        let fullPredicate = makePredicate(fingerprint: fingerprint)
        totalCount = try context.fetchCount(FetchDescriptor<CatalogueItem>(predicate: fullPredicate))
        hasMore = totalCount > 0

        if fingerprint.searchText.isEmpty {
            // No search: hasAnyItems is the same population as totalCount.
            // Skip the second fetchCount to save a DB round-trip.
            hasAnyItems = totalCount > 0
        } else {
            let noSearchPredicate = makePredicate(fingerprint: fingerprint, ignoreSearch: true)
            let anyCount = try context.fetchCount(FetchDescriptor<CatalogueItem>(predicate: noSearchPredicate))
            hasAnyItems = anyCount > 0
        }
    }

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

    // MARK: - Predicate Builders

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

    /// Builds the CatalogueItem predicate used for the custom-sort `totalCount`/`hasAnyItems`.
    /// Same catalogue/tab/search filter as `makePredicate`, plus a check that the item has
    /// a FieldValue for `fieldDefID` — matching exactly what loadMoreCustomSort can surface.
    private func makeCustomSortTotalCountPredicate(fingerprint: FilterFingerprint, fieldDefID: PersistentIdentifier, ignoreSearch: Bool = false) -> Predicate<CatalogueItem> {
        let targetID = fingerprint.catalogueID
        let filterAll = fingerprint.tab == .all
        let filterWishlist = fingerprint.tab == .wishlist
        let hasSearch = !fingerprint.searchText.isEmpty && !ignoreSearch
        let lowercasedQuery = fingerprint.searchText.lowercased()

        return #Predicate<CatalogueItem> { item in
            item.catalogue?.persistentModelID == targetID
                && item.deletedDate == nil
                && (filterAll || item.isWishlist == filterWishlist)
                && (!hasSearch || item.searchText.contains(lowercasedQuery))
                && item.fieldValues.contains(where: { $0.fieldDefinition.flatMap { $0.persistentModelID == fieldDefID } ?? false })
        }
    }

    /// Builds the FieldValue predicate for the custom sort path.
    ///
    /// Filters on `fv.fieldDefinition?.persistentModelID == fieldDefID` (the FK column)
    /// rather than a secondary UUID property, so the DB can satisfy the equality constraint
    /// directly from the FK index and then apply the compound #Index([\.fieldDefinition, \.sortKey]).
    ///
    /// Tab is encoded with literal `== true` / `== false` to avoid the Optional<Bool>
    /// type-inference issue that arises when capturing a Bool variable. Search filtering
    /// is intentionally omitted — it is applied in-memory in loadMoreCustomSort to avoid
    /// #Predicate compiler timeout on optional-chained .contains expressions.
    private func makeFieldValuePredicate(fieldDefID: PersistentIdentifier, tab: ItemTab) -> Predicate<FieldValue> {
        switch tab {
        case .all:
            return #Predicate<FieldValue> { fv in
                fv.fieldDefinition?.persistentModelID == fieldDefID && fv.item?.deletedDate == nil
            }
        case .wishlist:
            return #Predicate<FieldValue> { fv in
                fv.fieldDefinition?.persistentModelID == fieldDefID
                    && fv.item?.deletedDate == nil
                    && fv.item?.isWishlist == true
            }
        case .owned:
            return #Predicate<FieldValue> { fv in
                fv.fieldDefinition?.persistentModelID == fieldDefID
                    && fv.item?.deletedDate == nil
                    && fv.item?.isWishlist == false
            }
        }
    }
}
