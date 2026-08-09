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

    private var activeItems: [CatalogueItem] {
        catalogue.items.filter { $0.deletedDate == nil }
    }

    private var totalPhotos: Int {
        activeItems.reduce(0) { $0 + $1.photos.count }
    }

    private var sortedFields: [FieldDefinition] {
        catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
    }

    /// One row per status tab (excluding the synthetic "All"), so a catalogue tracking
    /// Owned/Wishlist/Ordered/Sold reports all four rather than a fixed pair.
    private var statusCounts: [(label: String, count: Int)] {
        catalogue.statusTabDescriptors
            .filter { $0.tab != .all }
            .compactMap { descriptor in
                guard let stored = descriptor.tab.storedValue else { return nil }
                return (descriptor.label, activeItems.count { $0.statusValue == stored })
            }
    }

    /// Flags are independent of status, so they're counted separately rather than
    /// partitioning the same total.
    private var flagCounts: [(label: String, count: Int)] {
        catalogue.flagFields.map { flag in
            let token = ItemFacetBuilder.flagToken(for: flag.fieldID)
            return (flag.name, activeItems.count { $0.flagKeys.contains(token) })
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Items") {
                    LabeledContent("Total", value: activeItems.count.formatted())
                    ForEach(statusCounts + flagCounts, id: \.label) { entry in
                        LabeledContent(entry.label, value: entry.count.formatted())
                    }
                    LabeledContent("Photos", value: totalPhotos.formatted())
                }

                if !sortedFields.isEmpty {
                    Section("Field Completion") {
                        ForEach(sortedFields) { field in
                            FieldCompletionRow(field: field, items: activeItems)
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
        let filled = items.count { item in
            item.value(for: field)?.displayValue(options: field.fieldOptions).isEmpty == false
        }
        return Double(filled) / Double(items.count) * 100
    }

    var body: some View {
        LabeledContent(field.name) {
            Text(completionRate.formatted(.number.precision(.fractionLength(0))) + "%")
                .foregroundStyle(completionRate == 100 ? Color.green : Color.secondary)
        }
    }
}
