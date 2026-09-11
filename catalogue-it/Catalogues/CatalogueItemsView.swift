//
//  CatalogueItemsView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/03/2026.
//

import SwiftUI
import SwiftData

/// The catalogue's items, with `header` scrolling away above them and `pinnedHeader`
/// following it up until it sticks under the navigation bar.
///
/// The header is the first thing in the scroll content rather than a pinned inset, so it
/// costs the user nothing once they start scrolling. `isHeaderScrolledAway` reports when
/// it has passed under the navigation bar, so the caller can put its title there instead.
struct CatalogueItemsView<Header: View, PinnedHeader: View>: View {
    let catalogue: Catalogue
    let statusTab: StatusTab
    let activeFlagIDs: [UUID]
    let searchText: String
    @Binding var sortFieldKey: String
    @Binding var sortDirection: String
    @Binding var selectedItem: CatalogueItem?
    @Binding var displayedCount: Int
    @Binding var isHeaderScrolledAway: Bool
    @ViewBuilder let header: Header
    @ViewBuilder let pinnedHeader: PinnedHeader

    @Environment(\.modelContext) private var modelContext
    @State private var pagination = ItemPaginationController()
    @State private var scrollPosition = ScrollPosition()
    // ID of the item the user tapped most recently. Used to restore scroll position
    // after a force reset (e.g. when the user edits an item and navigates back).
    @State private var scrollAnchorID: PersistentIdentifier?
    @State private var headerHeight: CGFloat = 0

    /// The header, measured so the scroll listener knows when it has gone.
    private var measuredHeader: some View {
        header.onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }
    }

    private var filterFingerprint: FilterFingerprint {
        FilterFingerprint(
            catalogueID: catalogue.persistentModelID,
            statusTab: statusTab,
            activeFlagIDs: activeFlagIDs,
            searchText: searchText,
            sortFieldKey: sortFieldKey,
            sortDirection: sortDirection
        )
    }

    var body: some View {
        Group {
            if pagination.items.isEmpty && !pagination.isLoadingMore {
                VStack(spacing: 0) {
                    measuredHeader
                    pinnedHeader
                    CatalogueEmptyStateView(
                        catalogue: catalogue,
                        statusTab: statusTab,
                        hasActiveFlags: !activeFlagIDs.isEmpty,
                        isFiltered: !searchText.isEmpty && pagination.hasAnyItems
                    )
                }
            } else {
                switch catalogue.itemLayout {
                case .grid:
                    ItemGridView(
                        items: pagination.items,
                        showStatusChip: statusTab == .all,
                        catalogue: catalogue,
                        selectedItem: $selectedItem,
                        scrollPosition: $scrollPosition,
                        hasMore: pagination.hasMore,
                        isLoadingMore: pagination.isLoadingMore,
                        onLoadMore: { pagination.loadMore(context: modelContext) },
                        header: { measuredHeader },
                        pinnedHeader: { pinnedHeader }
                    )
                case .list:
                    ItemListView(
                        items: pagination.items,
                        catalogue: catalogue,
                        showStatusChip: statusTab == .all,
                        selectedItem: $selectedItem,
                        scrollPosition: $scrollPosition,
                        hasMore: pagination.hasMore,
                        isLoadingMore: pagination.isLoadingMore,
                        onLoadMore: { pagination.loadMore(context: modelContext) },
                        header: { measuredHeader },
                        pinnedHeader: { pinnedHeader }
                    )
                }
            }
        }
        // The header's title sits at its vertical centre, so it is "gone" once half the header
        // has passed under the bar — that is when the bar's own title takes over. This listens
        // to every scroll view beneath it, so the cards must not grow a scroll view of their
        // own: a horizontal one would report an offset of zero and flip the state back.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > headerHeight / 2
        } action: { _, scrolledAway in
            guard scrolledAway != isHeaderScrolledAway else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isHeaderScrolledAway = scrolledAway }
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
            // The list may be replaced by the empty state, which never scrolls and so would
            // never report the header back.
            isHeaderScrolledAway = false
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
