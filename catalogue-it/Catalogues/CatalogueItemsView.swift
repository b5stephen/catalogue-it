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

    @Query private var items: [CatalogueItem]

    init(catalogue: Catalogue,
         tab: ItemTab,
         searchText: String,
         sortFieldKey: Binding<String>,
         sortDirection: Binding<String>,
         layout: ItemLayout,
         selectedItem: Binding<CatalogueItem?>) {

        self.catalogue = catalogue
        self.tab = tab
        self.searchText = searchText
        self._sortFieldKey = sortFieldKey
        self._sortDirection = sortDirection
        self.layout = layout
        self._selectedItem = selectedItem

        let isAll = tab == .all
        let isWishlist = tab == .wishlist

        let targetID = catalogue.persistentModelID
        let filterWishlist = isWishlist
        let filterAll = isAll

        // Filter by Catalogue ID and Tab
        // Note: Predicate body must be a single expression. Using persistentModelID for relationships.
        _items = Query(filter: #Predicate<CatalogueItem> { item in
            item.catalogue?.persistentModelID == targetID && (filterAll || item.isWishlist == filterWishlist)
        })
    }

    // Perform search and sort in memory for now, as dynamic predicates/sorts
    // on relationships/computed values are complex.
    // Since we've already filtered by Catalogue+Tab, the dataset is smaller.
    private var processedItems: [CatalogueItem] {
        // 1. Search
        let searched: [CatalogueItem]
        if searchText.isEmpty {
            searched = items
        } else {
            searched = items.filter { item in
                item.fieldValues.contains { $0.displayValue.localizedStandardContains(searchText) }
            }
        }

        // 2. Sort
        return sortedItems(searched)
    }

    private func sortedItems(_ items: [CatalogueItem]) -> [CatalogueItem] {
        let field = ItemSortField(rawValue: sortFieldKey)
        let asc = (ItemSortDirection(rawValue: sortDirection) ?? .ascending) == .ascending

        return items.sorted { a, b in
            let result: Bool
            switch field {
            case .dateAdded:
                result = a.createdDate < b.createdDate
            case .field(let fieldID):
                guard let def = catalogue.fieldDefinitions.first(where: { $0.fieldID == fieldID }) else {
                    return false
                }
                let va = a.value(for: def)
                let vb = b.value(for: def)
                guard let va else { return false }
                guard let vb else { return true }
                switch va.fieldType {
                case .text:
                    let ta = va.textValue ?? "", tb = vb.textValue ?? ""
                    result = ta.localizedCompare(tb) == .orderedAscending
                case .number:
                    result = (va.numberValue ?? 0) < (vb.numberValue ?? 0)
                case .date:
                    guard let da = va.dateValue, let db = vb.dateValue else {
                        return va.dateValue != nil
                    }
                    result = da < db
                case .boolean:
                    result = (va.boolValue == false) && (vb.boolValue == true)
                }
            }
            return asc ? result : !result
        }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        if processedItems.isEmpty {
            CatalogueEmptyStateView(
                selectedTab: tab,
                isFiltered: !searchText.isEmpty && !items.isEmpty
            )
        } else {
            switch layout {
            case .grid:
                ItemGridView(items: processedItems, gridColumns: gridColumns, showWishlistBadge: tab == .all, selectedItem: $selectedItem)
            case .list:
                ItemListView(items: processedItems, catalogue: catalogue, showWishlistBadge: tab == .all, selectedItem: $selectedItem)
            }
        }
    }
}
