//
//  ItemDetailView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Item Detail View

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let catalogue: Catalogue
    let item: CatalogueItem
    @Binding var selectedItem: CatalogueItem?

    @State private var showingEditItem = false
    @State private var showingDuplicateItem = false
    @State private var showingDeleteConfirmation = false

    // MARK: - Computed

    private var primaryValue: String {
        guard let firstDef = catalogue.fieldDefinitions
            .sorted(by: { $0.priority < $1.priority })
            .first,
              let val = item.value(for: firstDef),
              !val.displayValue(options: firstDef.fieldOptions).isEmpty
        else { return "Untitled Item" }
        return val.displayValue(options: firstDef.fieldOptions)
    }

    private var sortedPhotos: [ItemPhoto] {
        item.photos.sorted { $0.priority < $1.priority }
    }

    /// Field definitions paired with their values, filtered to non-empty entries only.
    private var displayFields: [(FieldDefinition, FieldValue)] {
        catalogue.fieldDefinitions
            .sorted { $0.priority < $1.priority }
            .compactMap { def in
                guard let val = item.value(for: def), !val.displayValue(options: def.fieldOptions).isEmpty else { return nil }
                return (def, val)
            }
    }

    private var shareText: String {
        var lines: [String] = []
        for def in catalogue.fieldDefinitions.sorted(by: { $0.priority < $1.priority }) {
            if let val = item.value(for: def) {
                lines.append("\(def.name): \(val.displayValue(options: def.fieldOptions))")
            }
        }
        if let notes = item.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !sortedPhotos.isEmpty {
                    PhotoCarouselView(photos: sortedPhotos)
                        .frame(height: AppConstants.PhotoHeight.detail)
                }

                VStack(alignment: .leading, spacing: 0) {
                    if !displayFields.isEmpty {
                        ItemFieldsSection(fields: displayFields)
                    }

                    if let notes = item.notes, !notes.isEmpty {
                        ItemNotesSection(notes: notes)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(primaryValue)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: shareText) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showingDuplicateItem = true
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More Options", systemImage: "ellipsis")
                }
                .confirmationDialog(
                    "Delete \"\(primaryValue)\"?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        selectedItem = nil
                        item.deletedDate = Date.now
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The item will be moved to Recently Deleted.")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditItem = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
#else
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShareLink(item: shareText) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showingDuplicateItem = true
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More Options", systemImage: "ellipsis.circle")
                }
                .confirmationDialog(
                    "Delete \"\(primaryValue)\"?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        selectedItem = nil
                        item.deletedDate = Date.now
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The item will be moved to Recently Deleted.")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditItem = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
#endif
        }
        .sheet(isPresented: $showingEditItem) {
            AddEditItemView(catalogue: catalogue, item: item)
        }
        .sheet(isPresented: $showingDuplicateItem) {
            AddEditItemView(catalogue: catalogue, duplicateSource: item)
        }
    }

}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field1 = FieldDefinition(name: "Manufacturer", fieldType: .text, priority: 0)
    field1.catalogue = catalogue
    container.mainContext.insert(field1)

    let field2 = FieldDefinition(name: "Year", fieldType: .number, priority: 1)
    field2.catalogue = catalogue
    container.mainContext.insert(field2)

    let field3 = FieldDefinition(name: "Assembled", fieldType: .boolean, priority: 2)
    field3.catalogue = catalogue
    container.mainContext.insert(field3)

    let item = CatalogueItem(isWishlist: false, notes: "Bought at the Hornby show, 2024.")
    item.catalogue = catalogue
    container.mainContext.insert(item)

    let val1 = FieldValue(fieldDefinition: field1, fieldType: .text)
    val1.textValue = "Airfix"
    val1.item = item
    container.mainContext.insert(val1)

    let val2 = FieldValue(fieldDefinition: field2, fieldType: .number)
    val2.numberValue = 1972
    val2.item = item
    container.mainContext.insert(val2)

    let val3 = FieldValue(fieldDefinition: field3, fieldType: .boolean)
    val3.boolValue = true
    val3.item = item
    container.mainContext.insert(val3)

    return NavigationStack {
        ItemDetailView(catalogue: catalogue, item: item, selectedItem: .constant(nil))
    }
    .modelContainer(container)
}
