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

        // Filter by Catalogue ID and Tab.
        // Note: Predicate body must be a single expression. Using persistentModelID for relationships.
        var descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { item in
                item.catalogue?.persistentModelID == targetID
                    && item.deletedDate == nil
                    && (filterAll || item.isWishlist == filterWishlist)
            }
        )
        // Batch-load field values to avoid N+1 queries during list render.
        // Photos are intentionally excluded: LazyVGrid/List only renders visible cells,
        // so prefetching all ItemPhoto objects upfront adds cost without benefit.
        descriptor.relationshipKeyPathsForPrefetching = [\.fieldValues]

        // Push dateAdded sort to SQLite via the index on createdDate.
        // Custom field sorts must remain in-memory (FieldValue properties aren't sortable at DB level).
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

    // Computes the filtered and sorted list from the current @Query results.
    // Must run on MainActor because CatalogueItem/FieldValue are @Model types.
    private func computeDisplayedItems() -> [CatalogueItem] {
        // 1. Search
        let searched: [CatalogueItem]
        if searchText.isEmpty {
            searched = items
        } else {
            searched = items.filter { item in
                catalogue.fieldDefinitions.contains { def in
                    guard let fv = item.value(for: def) else { return false }
                    return fv.displayValue(options: def.fieldOptions).localizedStandardContains(searchText)
                }
            }
        }

        // 2. Sort
        // dateAdded sort was applied at DB level in the FetchDescriptor — skip in-memory sort.
        let field = ItemSortField(rawValue: sortFieldKey)
        if case .dateAdded = field { return searched }
        let direction = ItemSortDirection(rawValue: sortDirection) ?? .ascending
        return CatalogueItemSort.sorted(searched, primaryField: field, direction: direction, catalogue: catalogue)
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
        // Recomputes search + sort whenever items, search, or sort settings change.
        // Task.yield() lets the navigation animation complete before the sort runs.
        .task(id: processingID) {
            await Task.yield()
            let result = computeDisplayedItems()
            displayedItems = result
            displayedCount = result.count
        }
    }
}
