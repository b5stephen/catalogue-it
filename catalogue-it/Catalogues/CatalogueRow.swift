//
//  CatalogueRow.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Catalogue Row

struct CatalogueRow: View {
    @Environment(\.modelContext) private var modelContext
    let catalogue: Catalogue

    /// Item count excluding soft-deleted items. Uses a DB fetchCount — no object
    /// materialisation — backed by #Index([\.catalogue, \.deletedDate, \.createdDate]).
    private var itemCount: Int {
        let id = catalogue.persistentModelID
        let descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == id && $0.deletedDate == nil }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
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
