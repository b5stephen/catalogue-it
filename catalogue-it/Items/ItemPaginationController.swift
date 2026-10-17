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

/// Any change resets pagination.
struct FilterFingerprint: Equatable {
    let catalogueID: PersistentIdentifier
    /// `.all` (or no status field) applies no status filter.
    let statusTab: StatusTab
    /// ANDed. Sorted by the initialiser so equality ignores toggle order.
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

    var flagTokens: [String] {
        activeFlagIDs.map { ItemFacetBuilder.flagToken(for: $0) }
    }
}

// MARK: - Item Pagination Controller

/// Offset-based pagination with sorting and filtering in the store:
/// - Date added: a `CatalogueItem` fetch.
/// - Custom field: a `FieldValue` fetch on the `[fieldDefinition, sortKey, tiebreakKey]` index,
///   so ties resolve in the fetch too. Items with no value for the field can't be reached that
///   way, so a tail pass appends them by `createdDate`, whichever the direction.
/// Status is in the predicate; search (custom sort only) and flags are applied in memory per
/// batch — see `matchesFlags`.
///
/// Reacts to `NSManagedObjectContextDidSave`, behind a count guard for date-added sort; a
/// custom sort always rebuilds, since editing the sort field reorders without changing the
/// count. `.remoteChangesMerged` always rebuilds: a remote edit can move an item between tabs
/// without changing the count.
@MainActor
@Observable
final class ItemPaginationController {

    static let pageSize = 50

    private(set) var items: [CatalogueItem] = []
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var totalCount = 0
    /// Tells "catalogue is empty" from "search found nothing".
    private(set) var hasAnyItems = false

    // DB rows fetched, not items appended: the in-memory filters can drop rows.
    private var dateAddedOffset = 0

    private var customSortOffset = 0
    private var customSortPredicate: Predicate<FieldValue>?
    // Decided once per reset from the counts, so the common case never scans for the tail. The
    // surfaced set skips items the stream produced, including a duplicate FieldValue's.
    private var customSortHasTail = false
    private var customSortInTail = false
    private var customSortTailOffset = 0
    private var customSortSurfacedIDs: Set<PersistentIdentifier> = []
    private var customSortFieldDefID: PersistentIdentifier?

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
        dateAddedOffset = 0
        customSortOffset = 0
        customSortPredicate = nil
        customSortFieldDefID = nil
        customSortHasTail = false
        customSortInTail = false
        customSortTailOffset = 0
        customSortSurfacedIDs = []
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
        }
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

        guard (try? matchingCount(fingerprint: fp, context: ctx)) != totalCount else { return }
        reset(fingerprint: fp, context: ctx, force: true)
    }

    // MARK: - Custom Sort Setup

    /// Counts come from the item side, the same population as the date-added path and the
    /// Catalogues screen. Search is applied in memory per batch: `.contains` through an
    /// optional chain times out the `#Predicate` compiler.
    private func setupCustomSort(fingerprint: FilterFingerprint, fieldID: UUID, context: ModelContext) throws {
        let catalogueID = fingerprint.catalogueID
        var fieldDesc = FetchDescriptor<FieldDefinition>(
            predicate: #Predicate { $0.fieldID == fieldID && $0.catalogue?.persistentModelID == catalogueID }
        )
        fieldDesc.fetchLimit = 1
        guard let resolvedField = try context.fetch(fieldDesc).first else {
            hasMore = false
            hasAnyItems = false
            totalCount = 0
            return
        }

        let fieldDefID = resolvedField.persistentModelID
        customSortFieldDefID = fieldDefID
        let predicate = makeFieldValuePredicate(fieldDefID: fieldDefID, statusTab: fingerprint.statusTab)
        customSortPredicate = predicate

        // Items with no FieldValue for the field are invisible to the stream (`contains(where:)`
        // over an optional to-many can't be expressed in #Predicate), so count from the item side.
        try setupDateAddedSort(fingerprint: fingerprint, context: context)

        // The stream count ignores search and flags, so it only proves the tail empty when neither
        // is active.
        let streamCount = try context.fetchCount(FetchDescriptor<FieldValue>(predicate: predicate))
        customSortHasTail = totalCount > streamCount
            || !fingerprint.searchText.isEmpty
            || !fingerprint.flagTokens.isEmpty
    }

    private func loadMoreCustomSort(fingerprint: FilterFingerprint, context: ModelContext) throws {
        guard let predicate = customSortPredicate else { hasMore = false; return }

        let ascending = (ItemSortDirection(rawValue: fingerprint.sortDirection) ?? .ascending) == .ascending
        let hasSearch = !fingerprint.searchText.isEmpty
        let query = SearchTextBuilder.queryVariants(fingerprint.searchText)
        let flagTokens = fingerprint.flagTokens

        // Loop until something is appended or the stream ends: the scroll sentinel only re-fires
        // when the list grows, so a page the filters empty would stall it.
        let countBeforeLoad = items.count
        repeat {
            if customSortInTail {
                try loadMoreCustomSortTail(fingerprint: fingerprint, context: context)
                continue
            }

            var desc = FetchDescriptor<FieldValue>(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\.sortKey, order: ascending ? .forward : .reverse),
                    SortDescriptor(\.tiebreakKey, order: .forward)
                ]
            )
            desc.fetchLimit = Self.pageSize
            desc.fetchOffset = customSortOffset
            desc.relationshipKeyPathsForPrefetching = [\.item]

            let fieldValues = try context.fetch(desc)
            customSortOffset += fieldValues.count

            // Touch fieldValues now: an item reached through `fv.item` may still be a fault, and its
            // row would render as "Untitled Item".
            items += fieldValues.compactMap { fv in
                guard let item = fv.item else { return nil }
                guard customSortSurfacedIDs.insert(item.persistentModelID).inserted else { return nil }
                if hasSearch, !matchesSearch(item, query) { return nil }
                if !matchesFlags(item, tokens: flagTokens) { return nil }
                _ = item.fieldValues
                return item
            }

            if fieldValues.count < Self.pageSize {
                customSortInTail = customSortHasTail
                hasMore = customSortHasTail
            }
        } while hasMore && items.count == countBeforeLoad
    }

    /// Items with no FieldValue for the sort field, in `createdDate` order. No predicate can
    /// express that, so it walks the catalogue, skipping most rows; it runs only when the counts
    /// say there is something to find, and prefetches nothing.
    private func loadMoreCustomSortTail(fingerprint: FilterFingerprint, context: ModelContext) throws {
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: makePredicate(fingerprint: fingerprint))
        descriptor.sortBy = [SortDescriptor(\.createdDate, order: .forward)]
        descriptor.fetchLimit = Self.pageSize
        descriptor.fetchOffset = customSortTailOffset

        let page = try context.fetch(descriptor)
        customSortTailOffset += page.count

        let flagTokens = fingerprint.flagTokens
        items += page.compactMap { item in
            guard !customSortSurfacedIDs.contains(item.persistentModelID),
                  matchesFlags(item, tokens: flagTokens) else { return nil }
            // Resolve the fault before the row renders, as in the stream path.
            _ = item.fieldValues
            return item
        }

        hasMore = page.count == Self.pageSize
    }

    // MARK: - Date Added Sort Setup

    private func setupDateAddedSort(fingerprint: FilterFingerprint, context: ModelContext) throws {
        totalCount = try matchingCount(fingerprint: fingerprint, context: context)
        hasMore = totalCount > 0

        if fingerprint.searchText.isEmpty {
            // No search: hasAnyItems is the same population as totalCount.
            hasAnyItems = totalCount > 0
        } else {
            let anyCount = try matchingCount(fingerprint: fingerprint, context: context, ignoreSearch: true)
            hasAnyItems = anyCount > 0
        }
    }

    private func loadMoreDateAdded(fingerprint: FilterFingerprint, context: ModelContext) throws {
        let ascending = (ItemSortDirection(rawValue: fingerprint.sortDirection) ?? .ascending) == .ascending
        let flagTokens = fingerprint.flagTokens

        // Loop for the same reason as loadMoreCustomSort.
        let countBeforeLoad = items.count
        repeat {
            var descriptor = FetchDescriptor<CatalogueItem>(predicate: makePredicate(fingerprint: fingerprint))
            descriptor.sortBy = [SortDescriptor(\.createdDate, order: ascending ? .forward : .reverse)]
            descriptor.fetchLimit = Self.pageSize
            descriptor.fetchOffset = dateAddedOffset
            // Every fetched item renders soon.
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

    /// The in-memory counterpart of the search clause in `makePredicate`.
    private func matchesSearch(_ item: CatalogueItem, _ query: (raw: String, canonical: String)) -> Bool {
        item.searchText.contains(query.raw) || item.searchText.contains(query.canonical)
    }

    /// Kept out of every `#Predicate`: it can't loop over a variable-length array, and even two
    /// written-out flag terms push the macro past the type-checker's time budget. Applied in
    /// memory to rows the predicate has already narrowed, which is why both load paths track an
    /// explicit DB offset.
    private func matchesFlags(_ item: CatalogueItem, tokens: [String]) -> Bool {
        tokens.allSatisfy { item.flagKeys.contains($0) }
    }

    /// With flags active the count needs a real fetch; `propertiesToFetch` keeps it to one column.
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

        // No status filter, so the fetch uses the [catalogue, deletedDate, createdDate] index.
        let statusFilter = fingerprint.statusTab.storedValue
        let hasStatus = statusFilter != nil
        let status = statusFilter ?? ""

        let hasSearch = !fingerprint.searchText.isEmpty && !ignoreSearch
        let (rawQuery, canonicalQuery) = SearchTextBuilder.queryVariants(fingerprint.searchText)

        return #Predicate { item in
            item.catalogue?.persistentModelID == targetID
                && item.deletedDate == nil
                && (!hasStatus || item.statusValue == status)
                && (!hasSearch || item.searchText.contains(rawQuery) || item.searchText.contains(canonicalQuery))
        }
    }

    /// Filters on the FieldDefinition FK, so the store can use the compound index. Status is in
    /// the predicate; search and flags are not — see `setupCustomSort`.
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
