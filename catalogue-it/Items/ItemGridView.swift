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
    @Binding var selectedItem: CatalogueItem?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(items) { item in
                    ItemCardView(item: item, showWishlistBadge: showWishlistBadge)
                        .onTapGesture { selectedItem = item }
                        .overlay {
                            if selectedItem == item {
                                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.medium)
                                    .strokeBorder(.tint, lineWidth: 2.5)
                            }
                        }
                }
            }
            .padding()
        }
    }
}
