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
                .foregroundStyle(Color(hex: catalogue.colorHex))
                .frame(width: 40, height: 40)
                .background(Color(hex: catalogue.colorHex).opacity(0.15))
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(catalogue.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label("\(catalogue.ownedItemCount)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("\(catalogue.wishlistItemCount)", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
