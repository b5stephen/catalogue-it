//
//  CatalogueItemsView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/03/2026.
//

import SwiftUI
import SwiftData

struct CatalogueItemsView: View {
    let catalogue: Catalogue
    let tab: ItemTab
    let searchText: String
    @Binding var sortFieldKey: String
    @Binding var sortDirection: String
    let layout: ItemLayout
    @Binding var selectedItem: CatalogueItem?
    @Binding var displayedCount: Int

    @Environment(\.modelContext) private var modelContext
    @Query private var items: [CatalogueItem]
    @State private var displayedItems: [CatalogueItem] = []

    init(catalogue: Catalogue,
         tab: ItemTab,
         searchText: String,
         sortFieldKey: Binding<String>,
         sortDirection: Binding<String>,
         layout: ItemLayout,
         selectedItem: Binding<CatalogueItem?>,
         displayedCount: Binding<Int>) {

        self.catalogue = catalogue
        self.tab = tab
        self.searchText = searchText
        self._sortFieldKey = sortFieldKey
        self._sortDirection = sortDirection
        self.layout = layout
        self._selectedItem = selectedItem
        self._displayedCount = displayedCount

        let isAll = tab == .all
        let isWishlist = tab == .wishlist

        let targetID = catalogue.persistentModelID
        let filterWishlist = isWishlist
        let filterAll = isAll

        let sortField = ItemSortField(rawValue: sortFieldKey.wrappedValue)
        let ascending = (ItemSortDirection(rawValue: sortDirection.wrappedValue) ?? .ascending) == .ascending

        // DB-level search: searchText is stored lowercased; query must match.
        let hasSearch = !searchText.isEmpty
        let lowercasedQuery = searchText.lowercased()

        // Filter by catalogue, tab, soft-delete, and (if active) search text.
        // Search uses CatalogueItem.searchText so SQLite filters without loading child rows.
        var descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { item in
                item.catalogue?.persistentModelID == targetID
                    && item.deletedDate == nil
                    && (filterAll || item.isWishlist == filterWishlist)
                    && (!hasSearch || item.searchText.contains(lowercasedQuery))
            }
        )
        // Batch-load field values to avoid N+1 queries during list render.
        // Photos are intentionally excluded: LazyVGrid/List only renders visible cells,
        // so prefetching all ItemPhoto objects upfront adds cost without benefit.
        descriptor.relationshipKeyPathsForPrefetching = [\.fieldValues]

        // Push dateAdded sort to SQLite via the index on createdDate.
        // Custom field sorts are handled in computeDisplayedItems() via a FieldValue fetch.
        if case .dateAdded = sortField {
            descriptor.sortBy = [SortDescriptor(\.createdDate, order: ascending ? .forward : .reverse)]
        }

        _items = Query(descriptor)
    }

    // Identifies the inputs that affect the displayed item list.
    // .task(id: processingID) restarts whenever any of these change.
    private struct ProcessingID: Equatable {
        let itemIDs: [PersistentIdentifier]
        let searchText: String
        let sortFieldKey: String
        let sortDirection: String
    }

    private var processingID: ProcessingID {
        ProcessingID(
            itemIDs: items.map(\.persistentModelID),
            searchText: searchText,
            sortFieldKey: sortFieldKey,
            sortDirection: sortDirection
        )
    }

    // Computes the sorted list from the current @Query results.
    // Search filtering is already applied at the DB level via the @Query predicate.
    // Must run on MainActor because CatalogueItem/FieldValue are @Model types.
    @MainActor
    private func computeDisplayedItems() -> [CatalogueItem] {
        let field = ItemSortField(rawValue: sortFieldKey)

        // dateAdded: @Query already applied DB-level sort — nothing to do.
        guard case .field(let fieldID) = field else { return items }

        // Custom field: fetch FieldValues sorted by sortKey at the DB level.
        // The @Query result set (items) is already filtered by tab and search;
        // use it as an allow-list to avoid a complex 3-level predicate traversal.
        let ascending = (ItemSortDirection(rawValue: sortDirection) ?? .ascending) == .ascending
        let filterAll = tab == .all
        let filterWishlist = tab == .wishlist

        var descriptor = FetchDescriptor<FieldValue>(
            predicate: #Predicate { fv in
                fv.fieldDefinition?.fieldID == fieldID
                    && fv.item?.deletedDate == nil
                    && (filterAll || fv.item?.isWishlist == filterWishlist)
            },
            sortBy: [SortDescriptor(\.sortKey, order: ascending ? .forward : .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.item]

        let candidateIDs = Set(items.map(\.persistentModelID))

        do {
            let sorted = try modelContext.fetch(descriptor)
            return sorted
                .compactMap { $0.item }
                .filter { candidateIDs.contains($0.persistentModelID) }
        } catch {
            return items // graceful fallback
        }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        Group {
            if displayedItems.isEmpty {
                CatalogueEmptyStateView(
                    selectedTab: tab,
                    isFiltered: !searchText.isEmpty && !items.isEmpty
                )
            } else {
                switch layout {
                case .grid:
                    ItemGridView(items: displayedItems, gridColumns: gridColumns, showWishlistBadge: tab == .all, selectedItem: $selectedItem)
                case .list:
                    ItemListView(items: displayedItems, catalogue: catalogue, showWishlistBadge: tab == .all, selectedItem: $selectedItem)
                }
            }
        }
        // Recomputes sort whenever items, search, or sort settings change.
        // Task.yield() lets the navigation animation complete before the sort runs.
        .task(id: processingID) {
            await Task.yield()
            let result = computeDisplayedItems()
            displayedItems = result
            displayedCount = result.count
        }
    }
}
