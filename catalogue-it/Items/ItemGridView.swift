//
//  CatalogueItemGridView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI

// MARK: - Item Grid View

struct ItemGridView: View {
    let items: [CatalogueItem]
    let gridColumns: [GridItem]
    let showWishlistBadge: Bool

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        ItemCardView(item: item, showWishlistBadge: showWishlistBadge)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}
