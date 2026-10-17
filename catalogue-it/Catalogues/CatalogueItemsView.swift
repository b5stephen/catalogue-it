//
//  CatalogueItemsView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/03/2026.
//

import SwiftUI
import SwiftData

/// `header` is the first thing in the scroll content, typically a spacer under whatever the
/// caller floats over the list; the scroll is reported through `scrollState` so it can collapse.
struct CatalogueItemsView<Header: View>: View {
    let catalogue: Catalogue
    let statusTab: StatusTab
    let activeFlagIDs: [UUID]
    let searchText: String
    @Binding var sortFieldKey: String
    @Binding var sortDirection: String
    @Binding var selectedItem: CatalogueItem?
    @Binding var displayedCount: Int
    let scrollState: BandScrollState
    /// Scrolling past this is of no interest to `scrollState`'s reader; zero stops the reports.
    let trackedScrollRange: CGFloat
    @ViewBuilder let header: Header

    @Environment(\.modelContext) private var modelContext
    @State private var pagination = ItemPaginationController()
    @State private var scrollPosition = ScrollPosition()
    // The most recently tapped item, to restore the scroll position after a force reset.
    @State private var scrollAnchorID: PersistentIdentifier?

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
                // In a scroll view like the lists it stands in for: bare, a landscape iPhone spun forever
                // laying out the push, re-resolving the bars against the band's spacer. At least the
                // visible height, so the message centres in what the header leaves.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            header
                            CatalogueEmptyStateView(
                                catalogue: catalogue,
                                statusTab: statusTab,
                                hasActiveFlags: !activeFlagIDs.isEmpty,
                                isFiltered: !searchText.isEmpty && pagination.hasAnyItems
                            )
                        }
                        .frame(minHeight: proxy.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
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
                        header: { header }
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
                        header: { header }
                    )
                }
            }
        }
        // Clamped, so the action stops firing past the range. It hears every scroll view beneath,
        // so the cards mustn't contain one: a horizontal one would report zero and snap the
        // caller's view back open.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            min(max(geometry.contentOffset.y + geometry.contentInsets.top, 0), trackedScrollRange)
        } action: { _, offset in
            scrollState.offset = offset
        }
        .task {
            pagination.reset(fingerprint: filterFingerprint, context: modelContext)
        }
        .onAppear {
            let didReset = pagination.startObservingStoreChanges()
            if didReset, let anchorID = scrollAnchorID {
                // A save happened behind a push and the list reloaded from page 1: load pages until the
                // edited item is back, then scroll to it.
                while !pagination.items.contains(where: { $0.persistentModelID == anchorID }),
                      pagination.hasMore {
                    pagination.loadMore(context: modelContext)
                }
                scrollPosition = ScrollPosition(id: anchorID)
                scrollAnchorID = nil
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            if let item = newItem {
                scrollAnchorID = item.persistentModelID
            }
        }
        .onChange(of: filterFingerprint) {
            scrollAnchorID = nil
            scrollPosition = ScrollPosition(edge: .top)
            // The empty state never scrolls, so it would never report the top back.
            scrollState.offset = 0
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
