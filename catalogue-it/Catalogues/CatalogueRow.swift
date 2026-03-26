//
//  CatalogueRow.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Catalogue Row

struct CatalogueRow: View {
    let catalogue: Catalogue

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
                let count = catalogue.items.count
                Text(count == 1 ? "1 item" : "\(count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("catalogue-\(catalogue.name)")
    }
}
