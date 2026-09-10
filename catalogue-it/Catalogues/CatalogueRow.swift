//
//  CatalogueRow.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Catalogue Row

/// The compact catalogue row, used on macOS where the sidebar is only ~200pt wide and cards
/// would be cramped. iOS and iPadOS use `CatalogueCardView` instead.
struct CatalogueRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    let catalogue: Catalogue

    private var itemCount: Int {
        CatalogueSummary.itemCount(for: catalogue, in: modelContext)
    }

    var body: some View {
        let palette = catalogue.palette(for: colorScheme)

        HStack(spacing: 12) {
            // The card's duotone gradient, shrunk to a tile: the sidebar is too narrow for a
            // full-colour row, but a catalogue should still look like itself on either platform.
            CatalogueIconView(iconName: catalogue.iconName, color: palette.iconGlyph, size: 22)
                .frame(width: 40, height: 40)
                .background(palette.fill)
                .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.small))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(catalogue.name)
                    .font(.headline)
                let count = itemCount
                Text(count == 1 ? "1 item" : "\(count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("catalogue-\(catalogue.name)")
    }
}
