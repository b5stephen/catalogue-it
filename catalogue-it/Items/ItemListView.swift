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

    var body: some View {
        List(selection: $selectedItem) {
            ForEach(items) { item in
                ItemRowView(item: item, catalogue: catalogue, showWishlistBadge: showWishlistBadge)
                    .tag(item)
            }
        }
        .listStyle(.plain)
    }
}
