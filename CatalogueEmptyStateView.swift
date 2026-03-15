//
//  CatalogueEmptyStateView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI

// MARK: - Empty State View

struct CatalogueEmptyStateView: View {
    let selectedTab: ItemTab
    let isFiltered: Bool

    var body: some View {
        if isFiltered {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView(
                "No Items Yet",
                systemImage: selectedTab == .owned ? "checkmark.circle" : "heart",
                description: Text(
                    selectedTab == .owned
                        ? "Tap + to add your first owned item"
                        : "Tap + to add your first wishlist item"
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
