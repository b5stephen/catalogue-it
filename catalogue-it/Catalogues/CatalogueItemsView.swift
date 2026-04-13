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
    @State private var scrollPosition = ScrollPosition()
    // ID of the item the user tapped most recently. Used to restore scroll position
    // after a force reset (e.g. when the user edits an item and navigates back).
    @State private var scrollAnchorID: PersistentIdentifier?

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
                        scrollPosition: $scrollPosition,
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
                        scrollPosition: $scrollPosition,
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
            let didReset = pagination.startObservingStoreChanges()
            if didReset, let anchorID = scrollAnchorID {
                // A save happened while we were behind a navigation push. The list was
                // reloaded from page 1. Load additional pages until the anchor item
                // (the one the user just edited) is back in the items array, then
                // scroll to it so the user is returned to roughly the same position.
                while !pagination.items.contains(where: { $0.persistentModelID == anchorID }),
                      pagination.hasMore {
                    pagination.loadMore(context: modelContext)
                }
                scrollPosition = ScrollPosition(id: anchorID)
                scrollAnchorID = nil
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            // Capture the tapped item's ID so we can restore position after an edit.
            if let item = newItem {
                scrollAnchorID = item.persistentModelID
            }
        }
        .onChange(of: filterFingerprint) {
            scrollAnchorID = nil
            scrollPosition = ScrollPosition(edge: .top)
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
