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
                systemImage: selectedTab == .owned ? "checkmark.circle" : selectedTab == .wishlist ? "heart" : "tray.2",
                description: Text(
                    selectedTab == .owned
                        ? "Tap + to add your first owned item"
                        : selectedTab == .wishlist
                            ? "Tap + to add your first wishlist item"
                            : "Tap + to add your first item"
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
