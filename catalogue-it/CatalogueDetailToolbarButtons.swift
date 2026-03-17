//
//  CatalogueDetailToolbarButtons.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 16/03/2026.
//

import SwiftUI

// MARK: - Edit Catalogue Button

struct CatalogueEditButton: View {
    @Binding var showingEditCatalogue: Bool

    var body: some View {
        Button {
            showingEditCatalogue = true
        } label: {
            Label("Edit Catalogue", systemImage: "pencil")
        }
    }
}

// MARK: - Layout Toggle Button

struct LayoutToggleButton: View {
    @Binding var layout: ItemLayout

    var body: some View {
        Button {
            layout = layout.next
        } label: {
            Label(layout.nextLayoutLabel, systemImage: layout.nextLayoutIcon)
        }
    }
}

// MARK: - Add Item Button

struct AddItemButton: View {
    @Binding var showingAddItem: Bool

    var body: some View {
        Button {
            showingAddItem = true
        } label: {
            Label("Add Item", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}

// MARK: - Sort Menu Button

struct SortMenuButton: View {
    let catalogue: Catalogue
    @Binding var sortFieldKey: String
    @Binding var sortDirection: String

    private var customFields: [FieldDefinition] {
        Array(
            catalogue.fieldDefinitions
                .sorted { $0.sortOrder < $1.sortOrder }
                .dropFirst()
        )
    }

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sortFieldKey) {
                Text("Date Added").tag(ItemSortField.dateAdded.rawValue)
                Text("Name").tag(ItemSortField.name.rawValue)
                ForEach(customFields) { field in
                    Text(field.name).tag(ItemSortField.field(field.name).rawValue)
                }
            }
            Picker("Direction", selection: $sortDirection) {
                Text("Ascending").tag(ItemSortDirection.ascending.rawValue)
                Text("Descending").tag(ItemSortDirection.descending.rawValue)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}
