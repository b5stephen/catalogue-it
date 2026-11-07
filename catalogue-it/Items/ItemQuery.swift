//
//  ItemQuery.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Filter Fingerprint

/// Any change resets pagination.
nonisolated struct FilterFingerprint: Equatable, Sendable {
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

    /// Sorted as the catalogue is.
    @MainActor
    init(catalogue: Catalogue, statusTab: StatusTab, activeFlagIDs: [UUID], searchText: String) {
        self.init(
            catalogueID: catalogue.persistentModelID,
            statusTab: statusTab,
            activeFlagIDs: activeFlagIDs,
            searchText: searchText,
            sortFieldKey: catalogue.sortFieldKey,
            sortDirection: catalogue.sortDirection
        )
    }

    var flagTokens: [String] {
        activeFlagIDs.map { ItemFacetBuilder.flagToken(for: $0) }
    }

    /// The same sort with no status, flag or search filter.
    var unfiltered: FilterFingerprint {
        FilterFingerprint(
            catalogueID: catalogueID,
            statusTab: .all,
            searchText: "",
            sortFieldKey: sortFieldKey,
            sortDirection: sortDirection
        )
    }

    /// Whether the two show the same set of items, whatever their order.
    func hasSameFilters(as other: FilterFingerprint) -> Bool {
        catalogueID == other.catalogueID
            && statusTab == other.statusTab
            && activeFlagIDs == other.activeFlagIDs
            && searchText == other.searchText
    }
}

// MARK: - Item Query

/// The items matching a `FilterFingerprint`, page by page in the list's sort order, on any
/// `ModelContext`. The list pages through it on the main context; selection, export and delete
/// drain it on a background one.
/// - Date added: a `CatalogueItem` fetch.
/// - Custom field: a `FieldValue` fetch on the `[fieldDefinition, sortKey, tiebreakKey]` index,
///   so ties resolve in the fetch too. Items with no value for the field can't be reached that
///   way, so a tail pass appends them by `createdDate`, whichever the direction.
/// Status is in the predicate; search (custom sort only) and flags are applied in memory per
/// batch — see `matchesFlags`.
nonisolated struct ItemQuery {
    static let defaultPageSize = 50
    private static let idPageSize = 500

    let fingerprint: FilterFingerprint
    private(set) var totalCount = 0
    /// Tells "catalogue is empty" from "search found nothing".
    private(set) var hasAnyItems = false
    private(set) var hasMore = false

    private let pageSize: Int
    /// Off, items come back without their values prefetched: for callers that read only IDs.
    private let loadsValues: Bool

    // DB rows fetched, not items returned: the in-memory filters can drop rows.
    private var dateAddedOffset = 0

    private var customSortOffset = 0
    private var customSortPredicate: Predicate<FieldValue>?
    // Decided once from the counts, so the common case never scans for the tail. The surfaced
    // set skips items the stream produced, including a duplicate FieldValue's.
    private var customSortHasTail = false
    private var customSortInTail = false
    private var customSortTailOffset = 0
    private var customSortSurfacedIDs: Set<PersistentIdentifier> = []

    init(
        fingerprint: FilterFingerprint,
        context: ModelContext,
        pageSize: Int = ItemQuery.defaultPageSize,
        loadsValues: Bool = true
    ) throws {
        self.fingerprint = fingerprint
        self.pageSize = pageSize
        self.loadsValues = loadsValues
        if case .field(let fieldID) = ItemSortField(rawValue: fingerprint.sortFieldKey) {
            try setupCustomSort(fieldID: fieldID, context: context)
        } else {
            try setupDateAddedSort(context: context)
        }
    }

    // MARK: - All IDs

    /// Every matching item's ID in list order, fetching no values. With `keeping`, only those IDs,
    /// stopping once they are all found.
    static func orderedIDs(
        for fingerprint: FilterFingerprint,
        context: ModelContext,
        keeping wanted: Set<PersistentIdentifier>? = nil
    ) throws -> [PersistentIdentifier] {
        var query = try ItemQuery(fingerprint: fingerprint, context: context, pageSize: idPageSize, loadsValues: false)
        var ids: [PersistentIdentifier] = []
        var found = 0
        while query.hasMore {
            try Task.checkCancellation()
            for item in try query.nextPage(context: context) {
                let id = item.persistentModelID
                if let wanted {
                    guard wanted.contains(id) else { continue }
                    found += 1
                }
                ids.append(id)
            }
            if let wanted, found >= wanted.count { break }
        }
        return ids
    }

    // MARK: - Paging

    /// Empty only when the query is exhausted: it keeps going past pages the in-memory filters
    /// empty, since the list's scroll sentinel only re-fires when the list grows.
    mutating func nextPage(context: ModelContext) throws -> [CatalogueItem] {
        var page: [CatalogueItem] = []
        while hasMore && page.isEmpty {
            if case .field = ItemSortField(rawValue: fingerprint.sortFieldKey) {
                page = try nextCustomSortPage(context: context)
            } else {
                page = try nextDateAddedPage(context: context)
            }
        }
        return page
    }

    private var ascending: Bool {
        (ItemSortDirection(rawValue: fingerprint.sortDirection) ?? .ascending) == .ascending
    }

    // MARK: - Custom Sort

    /// Counts come from the item side, the same population as the date-added path and the
    /// Catalogues screen. Search is applied in memory per batch: `.contains` through an
    /// optional chain times out the `#Predicate` compiler.
    private mutating func setupCustomSort(fieldID: UUID, context: ModelContext) throws {
        let catalogueID = fingerprint.catalogueID
        var fieldDesc = FetchDescriptor<FieldDefinition>(
            predicate: #Predicate { $0.fieldID == fieldID && $0.catalogue?.persistentModelID == catalogueID }
        )
        fieldDesc.fetchLimit = 1
        guard let resolvedField = try context.fetch(fieldDesc).first else { return }

        let predicate = Self.makeFieldValuePredicate(
            fieldDefID: resolvedField.persistentModelID, statusTab: fingerprint.statusTab)
        customSortPredicate = predicate

        // Items with no FieldValue for the field are invisible to the stream (`contains(where:)`
        // over an optional to-many can't be expressed in #Predicate), so count from the item side.
        try setupDateAddedSort(context: context)

        // The stream count ignores search and flags, so it only proves the tail empty when neither
        // is active.
        let streamCount = try context.fetchCount(FetchDescriptor<FieldValue>(predicate: predicate))
        customSortHasTail = totalCount > streamCount
            || !fingerprint.searchText.isEmpty
            || !fingerprint.flagTokens.isEmpty
    }

    private mutating func nextCustomSortPage(context: ModelContext) throws -> [CatalogueItem] {
        guard let predicate = customSortPredicate else { hasMore = false; return [] }
        if customSortInTail { return try nextCustomSortTailPage(context: context) }

        let hasSearch = !fingerprint.searchText.isEmpty
        let query = SearchTextBuilder.queryVariants(fingerprint.searchText)
        let flagTokens = fingerprint.flagTokens

        var desc = FetchDescriptor<FieldValue>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.sortKey, order: ascending ? .forward : .reverse),
                SortDescriptor(\.tiebreakKey, order: .forward)
            ]
        )
        desc.fetchLimit = pageSize
        desc.fetchOffset = customSortOffset
        desc.relationshipKeyPathsForPrefetching = [\.item]

        let fieldValues = try context.fetch(desc)
        customSortOffset += fieldValues.count

        // Touch fieldValues now: an item reached through `fv.item` may still be a fault, and its
        // row would render as "Untitled Item".
        let page: [CatalogueItem] = fieldValues.compactMap { fv in
            guard let item = fv.item else { return nil }
            guard customSortSurfacedIDs.insert(item.persistentModelID).inserted else { return nil }
            if hasSearch, !Self.matchesSearch(item, query) { return nil }
            if !Self.matchesFlags(item, tokens: flagTokens) { return nil }
            if loadsValues { _ = item.fieldValues }
            return item
        }

        if fieldValues.count < pageSize {
            customSortInTail = customSortHasTail
            hasMore = customSortHasTail
        }
        return page
    }

    /// Items with no FieldValue for the sort field, in `createdDate` order. No predicate can
    /// express that, so it walks the catalogue, skipping most rows; it runs only when the counts
    /// say there is something to find, and prefetches nothing.
    private mutating func nextCustomSortTailPage(context: ModelContext) throws -> [CatalogueItem] {
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: Self.makePredicate(fingerprint: fingerprint))
        descriptor.sortBy = [SortDescriptor(\.createdDate, order: .forward)]
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = customSortTailOffset

        let fetched = try context.fetch(descriptor)
        customSortTailOffset += fetched.count

        let flagTokens = fingerprint.flagTokens
        let page: [CatalogueItem] = fetched.compactMap { item in
            guard !customSortSurfacedIDs.contains(item.persistentModelID),
                  Self.matchesFlags(item, tokens: flagTokens) else { return nil }
            // Resolve the fault before the row renders, as in the stream path.
            if loadsValues { _ = item.fieldValues }
            return item
        }

        hasMore = fetched.count == pageSize
        return page
    }

    // MARK: - Date Added Sort

    private mutating func setupDateAddedSort(context: ModelContext) throws {
        totalCount = try Self.matchingCount(fingerprint: fingerprint, context: context)
        hasMore = totalCount > 0

        if fingerprint.searchText.isEmpty {
            // No search: hasAnyItems is the same population as totalCount.
            hasAnyItems = totalCount > 0
        } else {
            let anyCount = try Self.matchingCount(fingerprint: fingerprint, context: context, ignoreSearch: true)
            hasAnyItems = anyCount > 0
        }
    }

    private mutating func nextDateAddedPage(context: ModelContext) throws -> [CatalogueItem] {
        let flagTokens = fingerprint.flagTokens

        var descriptor = FetchDescriptor<CatalogueItem>(predicate: Self.makePredicate(fingerprint: fingerprint))
        descriptor.sortBy = [SortDescriptor(\.createdDate, order: ascending ? .forward : .reverse)]
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = dateAddedOffset
        if loadsValues {
            // Every fetched item renders soon.
            descriptor.relationshipKeyPathsForPrefetching = [\.storedFieldValues]
        } else {
            descriptor.propertiesToFetch = [\.flagKeys]
        }

        let fetched = try context.fetch(descriptor)
        dateAddedOffset += fetched.count
        hasMore = fetched.count == pageSize
        return flagTokens.isEmpty ? fetched : fetched.filter { Self.matchesFlags($0, tokens: flagTokens) }
    }

    // MARK: - Predicate Builders

    /// The in-memory counterpart of the search clause in `makePredicate`.
    private static func matchesSearch(_ item: CatalogueItem, _ query: (raw: String, canonical: String)) -> Bool {
        item.searchText.contains(query.raw) || item.searchText.contains(query.canonical)
    }

    /// Kept out of every `#Predicate`: it can't loop over a variable-length array, and even two
    /// written-out flag terms push the macro past the type-checker's time budget. Applied in
    /// memory to rows the predicate has already narrowed, which is why both load paths track an
    /// explicit DB offset.
    private static func matchesFlags(_ item: CatalogueItem, tokens: [String]) -> Bool {
        tokens.allSatisfy { item.flagKeys.contains($0) }
    }

    /// With flags active the count needs a real fetch; `propertiesToFetch` keeps it to one column.
    static func matchingCount(
        fingerprint: FilterFingerprint,
        context: ModelContext,
        ignoreSearch: Bool = false,
        ignoreFlags: Bool = false
    ) throws -> Int {
        let predicate = makePredicate(fingerprint: fingerprint, ignoreSearch: ignoreSearch)
        let tokens = ignoreFlags ? [] : fingerprint.flagTokens
        guard !tokens.isEmpty else {
            return try context.fetchCount(FetchDescriptor<CatalogueItem>(predicate: predicate))
        }
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: predicate)
        descriptor.propertiesToFetch = [\.flagKeys]
        return try context.fetch(descriptor).count { matchesFlags($0, tokens: tokens) }
    }

    private static func makePredicate(fingerprint: FilterFingerprint, ignoreSearch: Bool = false) -> Predicate<CatalogueItem> {
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
    private static func makeFieldValuePredicate(fieldDefID: PersistentIdentifier, statusTab: StatusTab) -> Predicate<FieldValue> {
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
