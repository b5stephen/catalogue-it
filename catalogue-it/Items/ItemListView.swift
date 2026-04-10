//
//  CatalogueItemListView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI

// MARK: - Item List View

struct ItemListView: View {
    let items: [CatalogueItem]
    let catalogue: Catalogue
    let showWishlistBadge: Bool
    @Binding var selectedItem: CatalogueItem?
    let hasMore: Bool
    let isLoadingMore: Bool
    let onLoadMore: () -> Void

#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
#if !os(macOS)
        if horizontalSizeClass == .compact {
            List {
                ForEach(items) { item in
                    ItemRowView(item: item, catalogue: catalogue, showWishlistBadge: showWishlistBadge)
                        .tag(item)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItem = item }
                }
                scrollSentinel
            }
            .listStyle(.plain)
        } else {
            regularList
        }
#else
        regularList
#endif
    }

    private var regularList: some View {
        List(selection: $selectedItem) {
            ForEach(items) { item in
                ItemRowView(item: item, catalogue: catalogue, showWishlistBadge: showWishlistBadge)
                    .tag(item)
            }
            scrollSentinel
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var scrollSentinel: some View {
        if hasMore {
            Color.clear
                .frame(height: 1)
                .listRowSeparator(.hidden)
                .onAppear { onLoadMore() }
        }
        if isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .padding()
        }
    }
}
