//
//  CatalogueStatsView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Catalogue Stats View

struct CatalogueStatsView: View {
    @Bindable var catalogue: Catalogue
    @Environment(\.dismiss) private var dismiss

    private var totalPhotos: Int {
        catalogue.items.reduce(0) { $0 + $1.photos.count }
    }

    private var sortedFields: [FieldDefinition] {
        catalogue.fieldDefinitions.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Items") {
                    LabeledContent("Total", value: catalogue.items.count.formatted())
                    LabeledContent("Owned", value: catalogue.ownedItemCount.formatted())
                    LabeledContent("Wishlist", value: catalogue.wishlistItemCount.formatted())
                    LabeledContent("Photos", value: totalPhotos.formatted())
                }

                if !sortedFields.isEmpty {
                    Section("Field Completion") {
                        ForEach(sortedFields) { field in
                            FieldCompletionRow(field: field, items: catalogue.items)
                        }
                    }
                }
            }
            .navigationTitle("Statistics")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Field Completion Row

private struct FieldCompletionRow: View {
    let field: FieldDefinition
    let items: [CatalogueItem]

    private var completionRate: Double {
        guard !items.isEmpty else { return 0 }
        let filled = items.filter { item in
            item.value(for: field.name)?.displayValue.isEmpty == false
        }.count
        return Double(filled) / Double(items.count) * 100
    }

    var body: some View {
        LabeledContent(field.name) {
            Text(completionRate.formatted(.number.precision(.fractionLength(0))) + "%")
                .foregroundStyle(completionRate == 100 ? Color.green : Color.secondary)
        }
    }
}
