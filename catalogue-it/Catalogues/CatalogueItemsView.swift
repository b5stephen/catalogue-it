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
    @State private var pagination = ItemPaginationController()

    private var filterFingerprint: FilterFingerprint {
        FilterFingerprint(
            catalogueID: catalogue.persistentModelID,
            tab: tab,
            searchText: searchText,
            sortFieldKey: sortFieldKey,
            sortDirection: sortDirection
        )
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        Group {
            if pagination.items.isEmpty && !pagination.isLoadingMore {
                CatalogueEmptyStateView(
                    selectedTab: tab,
                    isFiltered: !searchText.isEmpty && pagination.hasAnyItems
                )
            } else {
                switch layout {
                case .grid:
                    ItemGridView(
                        items: pagination.items,
                        gridColumns: gridColumns,
                        showWishlistBadge: tab == .all,
                        selectedItem: $selectedItem,
                        hasMore: pagination.hasMore,
                        isLoadingMore: pagination.isLoadingMore,
                        onLoadMore: { pagination.loadMore(context: modelContext) }
                    )
                case .list:
                    ItemListView(
                        items: pagination.items,
                        catalogue: catalogue,
                        showWishlistBadge: tab == .all,
                        selectedItem: $selectedItem,
                        hasMore: pagination.hasMore,
                        isLoadingMore: pagination.isLoadingMore,
                        onLoadMore: { pagination.loadMore(context: modelContext) }
                    )
                }
            }
        }
        .task {
            pagination.reset(fingerprint: filterFingerprint, context: modelContext)
        }
        .onAppear {
            pagination.startObservingStoreChanges()
        }
        .onChange(of: filterFingerprint) {
            pagination.reset(fingerprint: filterFingerprint, context: modelContext)
        }
        .onChange(of: pagination.totalCount) {
            displayedCount = pagination.totalCount
        }
        .onDisappear {
            pagination.stopObservingStoreChanges()
        }
    }
}
