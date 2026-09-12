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
    /// Selected status tab. `.all` (or a catalogue with no status field) applies no status filter.
    let statusTab: StatusTab
    /// `fieldID`s of the flag filters currently switched on, ANDed together.
    /// Kept sorted by the initialiser so equality doesn't depend on toggle order.
    let activeFlagIDs: [UUID]
    let searchText: String
    let sortFieldKey: String
    let sortDirection: String

    init(
        catalogueID: PersistentIdentifier,
        statusTab: StatusTab,
        activeFlagIDs: [UUID] = [],
        searchText: String,
        sortFieldKey: String,
        sortDirection: String
    ) {
        self.catalogueID = catalogueID
        self.statusTab = statusTab
        self.activeFlagIDs = activeFlagIDs.sorted { $0.uuidString < $1.uuidString }
        self.searchText = searchText
        self.sortFieldKey = sortFieldKey
        self.sortDirection = sortDirection
    }

    /// Flag tokens to match against `CatalogueItem.flagKeys`, in stable order.
    var flagTokens: [String] {
        activeFlagIDs.map { ItemFacetBuilder.flagToken(for: $0) }
    }
}

// MARK: - Item Pagination Controller

/// Manages offset-based pagination for the catalogue item list.
///
/// Both sort paths (dateAdded and custom field) produce a globally correct sort order
/// using DB-side sorting and filtering — no full in-memory scan:
/// - dateAdded: FetchDescriptor with sortBy + fetchLimit/fetchOffset on CatalogueItem.
/// - Custom field: FetchDescriptor with sortBy + fetchLimit/fetchOffset on FieldValue,
///   leveraging the #Index([\.fieldDefinition, \.sortKey, \.tiebreakKey]) compound index.
///   Sorting by both `sortKey` (the selected field's own value) and `tiebreakKey` (every
///   other field, in priority order, then dateAdded) means ties on the primary field are
///   still resolved entirely in the DB fetch — no in-memory re-sort. Status-tab filtering is
///   pushed to the DB predicate (an indexed column comparison on `statusValue`); search and
///   flag filtering are applied in-memory on each fetched batch (50 rows) to avoid #Predicate
///   macro compiler timeout on complex optional chains.
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
    // Explicit DB fetch offset for the dateAdded path. Tracked separately from items.count
    // because in-memory flag filtering (see matchesFlags) can drop fetched rows.
    private var dateAddedOffset = 0

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

    isolated deinit {
        // onDisappear doesn't always precede release (see `reset`), so drop the tokens here
        // too rather than leaving them registered with NotificationCenter.
        (observers + [standbyObserver].compactMap { $0 }).forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

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
        dateAddedOffset = 0
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

        // A reset means this list is being displayed, so it must hear the saves that follow.
        // Normally onAppear has already armed the observer, but pushing the content column
        // in compact width can fire onAppear and onDisappear back to back — and cancel the
        // view's task — for a view that nonetheless stays on screen. Left in standby, the
        // catalogue's first saved item would never show. Nothing is pending: the load above
        // just read the store.
        if observers.isEmpty, standbyObserver != nil {
            pendingStoreChange = false
            startObservingStoreChanges()
        }
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
        guard (try? matchingCount(fingerprint: fp, context: ctx)) != totalCount else { return }
        reset(fingerprint: fp, context: ctx, force: true)
    }

    // MARK: - Custom Sort Setup

    /// Resolves the FieldDefinition for the active sort field, pre-computes the FieldValue
    /// predicate (tab-filtered, DB-sorted), and initialises totalCount and hasAnyItems.
    ///
    /// The FieldValue predicate uses the #Index([\.fieldDefinition, \.sortKey, \.tiebreakKey])
    /// compound index on FieldValue via the fieldID equality constraint. Search filtering is
    /// deferred to loadMoreCustomSort (in-memory on each 50-row batch) to avoid #Predicate
    /// compiler timeout on optional-chained .contains expressions.
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
        customSortPredicate = makeFieldValuePredicate(fieldDefID: fieldDefID, statusTab: fingerprint.statusTab)

        // totalCount mirrors the same catalogue/tab/search filter as the dateAdded path,
        // but additionally requires a FieldValue for the sort field — items without one
        // are never surfaced by loadMoreCustomSort's FieldValue-based fetch, so counting
        // them here would show a total the user can never fully scroll to.
        totalCount = try customSortMatchingCount(fingerprint: fingerprint, fieldDefID: fieldDefID, context: context)
        hasMore = totalCount > 0

        if fingerprint.searchText.isEmpty {
            hasAnyItems = totalCount > 0
        } else {
            let anyCount = try customSortMatchingCount(
                fingerprint: fingerprint,
                fieldDefID: fieldDefID,
                context: context,
                ignoreSearch: true
            )
            hasAnyItems = anyCount > 0
        }
    }

    /// Custom-sort counterpart to `matchingCount`.
    ///
    /// Counted from the FieldValue side rather than through a `CatalogueItem` predicate that
    /// tests the relationship. Now that the relationship is optional (CloudKit requires it),
    /// `contains(where:)` over it cannot be expressed in `#Predicate` at all — the composed
    /// expression does not conform to `StandardPredicateExpression`. Counting the FieldValues
    /// for the sort field is equivalent: `loadMoreCustomSort` surfaces exactly one item per
    /// such FieldValue, which is the population this count exists to describe.
    ///
    /// `makeFieldValuePredicate` already applies the sort field, soft-delete and status-tab
    /// filters in the DB (the field belongs to one catalogue, so the catalogue filter is
    /// implied). Search and flags stay in memory, matching `loadMoreCustomSort` — and when
    /// neither is active this remains a plain `fetchCount`, as before.
    private func customSortMatchingCount(
        fingerprint: FilterFingerprint,
        fieldDefID: PersistentIdentifier,
        context: ModelContext,
        ignoreSearch: Bool = false
    ) throws -> Int {
        let predicate = makeFieldValuePredicate(fieldDefID: fieldDefID, statusTab: fingerprint.statusTab)
        let tokens = fingerprint.flagTokens
        let query = (ignoreSearch || fingerprint.searchText.isEmpty)
            ? nil
            : fingerprint.searchText.lowercased()

        guard query != nil || !tokens.isEmpty else {
            return try context.fetchCount(FetchDescriptor<FieldValue>(predicate: predicate))
        }

        var descriptor = FetchDescriptor<FieldValue>(predicate: predicate)
        descriptor.relationshipKeyPathsForPrefetching = [\.item]
        return try context.fetch(descriptor).count { fv in
            guard let item = fv.item else { return false }
            if let query, !item.searchText.contains(query) { return false }
            if !tokens.isEmpty, !matchesFlags(item, tokens: tokens) { return false }
            return true
        }
    }

    private func loadMoreCustomSort(fingerprint: FilterFingerprint, context: ModelContext) throws {
        guard let predicate = customSortPredicate else { hasMore = false; return }

        let ascending = (ItemSortDirection(rawValue: fingerprint.sortDirection) ?? .ascending) == .ascending
        let hasSearch = !fingerprint.searchText.isEmpty
        let lowercasedQuery = fingerprint.searchText.lowercased()
        // Flags are applied here rather than in the predicate — see matchesFlags.
        let flagTokens = fingerprint.flagTokens

        // Keep fetching DB pages until at least one item is appended or the FieldValue
        // stream is exhausted. A single page can match zero search results while more
        // matches exist further down; without the loop that would append nothing yet
        // leave hasMore true, and the scroll sentinel (which only re-fires onLoadMore
        // when the list grows) would stall forever.
        let countBeforeLoad = items.count
        repeat {
            var desc = FetchDescriptor<FieldValue>(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\.sortKey, order: ascending ? .forward : .reverse),
                    SortDescriptor(\.tiebreakKey, order: .forward)
                ]
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
            items += fieldValues.compactMap { fv in
                guard let item = fv.item else { return nil }
                if hasSearch, !item.searchText.contains(lowercasedQuery) { return nil }
                if !matchesFlags(item, tokens: flagTokens) { return nil }
                _ = item.fieldValues
                return item
            }

            hasMore = fieldValues.count == Self.pageSize
        } while hasMore && items.count == countBeforeLoad
    }

    // MARK: - Date Added Sort Setup

    private func setupDateAddedSort(fingerprint: FilterFingerprint, context: ModelContext) throws {
        totalCount = try matchingCount(fingerprint: fingerprint, context: context)
        hasMore = totalCount > 0

        if fingerprint.searchText.isEmpty {
            // No search: hasAnyItems is the same population as totalCount.
            // Skip the second fetchCount to save a DB round-trip.
            hasAnyItems = totalCount > 0
        } else {
            let anyCount = try matchingCount(fingerprint: fingerprint, context: context, ignoreSearch: true)
            hasAnyItems = anyCount > 0
        }
    }

    private func loadMoreDateAdded(fingerprint: FilterFingerprint, context: ModelContext) throws {
        let ascending = (ItemSortDirection(rawValue: fingerprint.sortDirection) ?? .ascending) == .ascending
        let flagTokens = fingerprint.flagTokens

        // Same shape as loadMoreCustomSort: keep fetching DB pages until at least one item
        // is appended or the stream is exhausted. Without the loop, a page that the flag
        // filter empties entirely would append nothing while leaving hasMore true, and the
        // scroll sentinel (which only re-fires when the list grows) would stall.
        let countBeforeLoad = items.count
        repeat {
            var descriptor = FetchDescriptor<CatalogueItem>(predicate: makePredicate(fingerprint: fingerprint))
            descriptor.sortBy = [SortDescriptor(\.createdDate, order: ascending ? .forward : .reverse)]
            descriptor.fetchLimit = Self.pageSize
            // dateAddedOffset tracks DB rows fetched rather than items appended, so the
            // offset stays correct when the in-memory flag filter drops rows.
            descriptor.fetchOffset = dateAddedOffset
            // Prefetch fieldValues for this page: all fetched items will render soon
            // (user is at or near the top on first page, near bottom on subsequent pages).
            descriptor.relationshipKeyPathsForPrefetching = [\.storedFieldValues]

            let page = try context.fetch(descriptor)
            dateAddedOffset += page.count

            if flagTokens.isEmpty {
                items.append(contentsOf: page)
            } else {
                items.append(contentsOf: page.filter { matchesFlags($0, tokens: flagTokens) })
            }

            hasMore = page.count == Self.pageSize
        } while hasMore && items.count == countBeforeLoad
    }

    // MARK: - Predicate Builders

    /// Flag filtering is deliberately kept out of every `#Predicate`.
    ///
    /// `#Predicate` is a macro over a fixed expression tree — it can't loop over a
    /// variable-length array — so each active flag would need its own written-out term.
    /// Adding even two pushes the macro-expanded predicate past the Swift type-checker's
    /// time budget and the file stops compiling. Flags are therefore applied in memory to
    /// each fetched batch, which is why both load paths track an explicit DB offset rather
    /// than deriving it from `items.count`.
    ///
    /// The cost is bounded: flags only filter rows the DB predicate has already narrowed to
    /// one catalogue, one status tab, and the active search.
    private func matchesFlags(_ item: CatalogueItem, tokens: [String]) -> Bool {
        tokens.allSatisfy { item.flagKeys.contains($0) }
    }

    /// Counts items matching the whole fingerprint, flags included.
    ///
    /// Falls back to `fetchCount` when no flag is active. With flags, the count has to come
    /// from an actual fetch since the predicate can't express them — `propertiesToFetch`
    /// keeps that to the one column being tested rather than materialising whole rows.
    private func matchingCount(
        fingerprint: FilterFingerprint,
        context: ModelContext,
        ignoreSearch: Bool = false
    ) throws -> Int {
        let predicate = makePredicate(fingerprint: fingerprint, ignoreSearch: ignoreSearch)
        let tokens = fingerprint.flagTokens
        guard !tokens.isEmpty else {
            return try context.fetchCount(FetchDescriptor<CatalogueItem>(predicate: predicate))
        }
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: predicate)
        descriptor.propertiesToFetch = [\.flagKeys]
        return try context.fetch(descriptor).count { matchesFlags($0, tokens: tokens) }
    }

    private func makePredicate(fingerprint: FilterFingerprint, ignoreSearch: Bool = false) -> Predicate<CatalogueItem> {
        let targetID = fingerprint.catalogueID

        // `.all` (and a catalogue with no status field) applies no status filter, so the
        // fetch falls through to the [catalogue, deletedDate, createdDate] index instead.
        let statusFilter = fingerprint.statusTab.storedValue
        let hasStatus = statusFilter != nil
        let status = statusFilter ?? ""

        let hasSearch = !fingerprint.searchText.isEmpty && !ignoreSearch
        let lowercasedQuery = fingerprint.searchText.lowercased()

        return #Predicate { item in
            item.catalogue?.persistentModelID == targetID
                && item.deletedDate == nil
                && (!hasStatus || item.statusValue == status)
                && (!hasSearch || item.searchText.contains(lowercasedQuery))
        }
    }

    /// Builds the FieldValue predicate for the custom sort path.
    ///
    /// Filters on `fv.fieldDefinition?.persistentModelID == fieldDefID` (the FK column)
    /// rather than a secondary UUID property, so the DB can satisfy the equality constraint
    /// directly from the FK index and then apply the compound
    /// #Index([\.fieldDefinition, \.sortKey, \.tiebreakKey]).
    ///
    /// The status tab is pushed to the DB — it's a single indexed column comparison and
    /// the dominant filter. Search and flag filtering are intentionally omitted and applied
    /// in-memory in loadMoreCustomSort instead: both are `.contains` over an optional-chained
    /// relationship (`fv.item?.…`), the exact shape that triggers #Predicate compiler
    /// timeouts here. loadMoreCustomSort already tracks an explicit DB offset, so filtering
    /// after the fetch keeps pagination correct.
    private func makeFieldValuePredicate(fieldDefID: PersistentIdentifier, statusTab: StatusTab) -> Predicate<FieldValue> {
        guard let status = statusTab.storedValue else {
            return #Predicate<FieldValue> { fv in
                fv.fieldDefinition?.persistentModelID == fieldDefID && fv.item?.deletedDate == nil
            }
        }
        return #Predicate<FieldValue> { fv in
            fv.fieldDefinition?.persistentModelID == fieldDefID
                && fv.item?.deletedDate == nil
                && fv.item?.statusValue == status
        }
    }
}
