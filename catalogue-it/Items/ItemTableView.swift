//
//  CatalogueItemTableView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 17/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Catalogue Item Table View

struct ItemTableView: View {
    let items: [CatalogueItem]
    let catalogue: Catalogue
    let showWishlistBadge: Bool
    @Binding var selectedItem: CatalogueItem?
    @Binding var sortFieldKey: String
    @Binding var sortDirection: String
    @Binding var isEditing: Bool
    var onViewDetails: ((CatalogueItem) -> Void)? = nil

    @State private var tableSortOrder: [CatalogueItemComparator] = []

    private var sortedFields: [FieldDefinition] {
        catalogue.fieldDefinitions.sorted { $0.sortOrder < $1.sortOrder }
    }

    // Bridges CatalogueItem? binding to the PersistentIdentifier? that Table requires.
    private var tableSelection: Binding<PersistentIdentifier?> {
        Binding(
            get: { selectedItem?.id },
            set: { id in selectedItem = id.flatMap { id in items.first { $0.id == id } } }
        )
    }

    var body: some View {
        Table(items, selection: tableSelection, sortOrder: $tableSortOrder) {
            TableColumnForEach(sortedFields) { field in
                TableColumn(field.name, sortUsing: CatalogueItemComparator(field: .field(field.name))) { item in
                    InlineFieldCell(item: item, field: field, isEditing: isEditing)
                }
            }

            // Optional wishlist column
            if showWishlistBadge {
                TableColumn("") { item in
                    WishlistToggleCell(item: item, isEditing: isEditing)
                }
                .width(isEditing ? 44 : 28)
            }
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { selection in
            if let id = selection.first,
               let item = items.first(where: { $0.id == id }),
               let onViewDetails {
                Button("View Details", systemImage: "info.circle") {
                    onViewDetails(item)
                }
            }
        }
        .onChange(of: tableSortOrder) { _, newValue in
            guard let first = newValue.first else { return }
            sortFieldKey = first.field.rawValue
            sortDirection = first.order == .forward
                ? ItemSortDirection.ascending.rawValue
                : ItemSortDirection.descending.rawValue
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                tableSortOrder = []
            } else {
                syncTableSortOrder()
            }
        }
        .onChange(of: sortFieldKey) { syncTableSortOrder() }
        .onChange(of: sortDirection) { syncTableSortOrder() }
        .onAppear { syncTableSortOrder() }
    }

    private func syncTableSortOrder() {
        let field = ItemSortField(rawValue: sortFieldKey)
        let direction = ItemSortDirection(rawValue: sortDirection) ?? .ascending
        let order: SortOrder = direction == .ascending ? .forward : .reverse
        let comparator = CatalogueItemComparator(field: field, order: order)
        if tableSortOrder.first != comparator {
            tableSortOrder = [comparator]
        }
    }
}
