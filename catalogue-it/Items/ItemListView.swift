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
        }
        .listStyle(.plain)
    }
}
