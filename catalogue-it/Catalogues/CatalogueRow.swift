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
    let catalogue: Catalogue

    private var itemCount: Int {
        CatalogueSummary.itemCount(for: catalogue, in: modelContext)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon with color
            Image(systemName: catalogue.iconName)
                .font(.title2)
                .foregroundStyle(catalogue.color)
                .frame(width: 40, height: 40)
                .background(catalogue.color.opacity(0.15))
                .clipShape(.rect(cornerRadius: 8))
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
