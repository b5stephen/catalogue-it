//
//  CatalogueItemListView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI

// MARK: - Item List View

struct CatalogueItemListView: View {
    let items: [CatalogueItem]
    let catalogue: Catalogue
    let showWishlistBadge: Bool

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    ItemRowView(item: item, catalogue: catalogue, showWishlistBadge: showWishlistBadge)
                }
            }
        }
        .listStyle(.plain)
    }
}
