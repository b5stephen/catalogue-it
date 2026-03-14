//
//  AddEditItemView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Add Edit Item View

struct AddEditItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let catalogue: Catalogue
    let existingItem: CatalogueItem?
    let defaultIsWishlist: Bool

    // MARK: - Form State

    @State private var fieldDrafts: [FieldValueDraft] = []
    @State private var photoDrafts: [PhotoDraft] = []
    @State private var isWishlist: Bool = false
    @State private var notes: String = ""

    // MARK: - Computed

    private var isEditing: Bool { existingItem != nil }

    init(catalogue: Catalogue, item: CatalogueItem? = nil, defaultIsWishlist: Bool = false) {
        self.catalogue = catalogue
        self.existingItem = item
        self.defaultIsWishlist = defaultIsWishlist
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                PhotoPickerView(photos: $photoDrafts)

                Section("Details") {
                    ForEach($fieldDrafts) { $draft in
                        FieldInputView(draft: $draft)
                    }
                }

                Section("Item Info") {
                    Toggle("Add to Wishlist", isOn: $isWishlist)
                }

                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveItem()
                    }
                }
            }
            .onAppear {
                loadItemData()
            }
        }
    }

    // MARK: - Load

    private func loadItemData() {
        let sortedDefs = catalogue.fieldDefinitions.sorted { $0.sortOrder < $1.sortOrder }

        if let item = existingItem {
            // Edit mode: populate from existing item
            fieldDrafts = sortedDefs.map { def in
                var draft = FieldValueDraft(
                    fieldName: def.name,
                    fieldType: def.fieldType,
                    sortOrder: def.sortOrder
                )
                if let fv = item.value(for: def.name) {
                    switch def.fieldType {
                    case .text:
                        draft.textValue = fv.textValue ?? ""
                    case .number:
                        draft.numberText = fv.numberValue.map { formatNumber($0) } ?? ""
                    case .date:
                        draft.dateValue = fv.dateValue ?? .now
                    case .boolean:
                        draft.boolValue = fv.boolValue ?? false
                    }
                }
                return draft
            }

            photoDrafts = item.photos
                .sorted { $0.sortOrder < $1.sortOrder }
                .enumerated()
                .map { index, photo in
                    PhotoDraft(
                        imageData: photo.imageData,
                        caption: photo.caption ?? "",
                        sortOrder: index
                    )
                }

            isWishlist = item.isWishlist
            notes = item.notes ?? ""
        } else {
            // Create mode: blank drafts
            fieldDrafts = sortedDefs.map { def in
                FieldValueDraft(fieldName: def.name, fieldType: def.fieldType, sortOrder: def.sortOrder)
            }
            isWishlist = defaultIsWishlist
        }
    }

    // MARK: - Save

    private func saveItem() {
        let targetItem: CatalogueItem

        if let existing = existingItem {
            // Edit path
            existing.isWishlist = isWishlist
            existing.notes = notes.isEmpty ? nil : notes

            for fv in existing.fieldValues { modelContext.delete(fv) }
            for photo in existing.photos { modelContext.delete(photo) }

            targetItem = existing
        } else {
            // Create path
            let newItem = CatalogueItem(
                isWishlist: isWishlist,
                notes: notes.isEmpty ? nil : notes
            )
            newItem.catalogue = catalogue
            modelContext.insert(newItem)
            targetItem = newItem
        }

        // Field values
        for draft in fieldDrafts {
            let fv = FieldValue(fieldName: draft.fieldName, fieldType: draft.fieldType, sortOrder: draft.sortOrder)
            switch draft.fieldType {
            case .text:
                fv.textValue = draft.textValue.isEmpty ? nil : draft.textValue
            case .number:
                fv.numberValue = Double(draft.numberText)
            case .date:
                fv.dateValue = draft.dateValue
            case .boolean:
                fv.boolValue = draft.boolValue
            }
            fv.item = targetItem
            modelContext.insert(fv)
        }

        // Photos
        for draft in photoDrafts {
            let photo = ItemPhoto(
                imageData: draft.imageData,
                sortOrder: draft.sortOrder,
                caption: draft.caption.isEmpty ? nil : draft.caption
            )
            photo.item = targetItem
            modelContext.insert(photo)
        }

        dismiss()
    }

    // MARK: - Helpers

    /// Formats a Double for display in the number text field, stripping unnecessary trailing ".0".
    private func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(value)
    }
}

// MARK: - Preview

#Preview("New Item") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field1 = FieldDefinition(name: "Manufacturer", fieldType: .text, sortOrder: 0)
    field1.catalogue = catalogue
    container.mainContext.insert(field1)

    let field2 = FieldDefinition(name: "Year", fieldType: .number, sortOrder: 1)
    field2.catalogue = catalogue
    container.mainContext.insert(field2)

    let field3 = FieldDefinition(name: "Assembled", fieldType: .boolean, sortOrder: 2)
    field3.catalogue = catalogue
    container.mainContext.insert(field3)

    return AddEditItemView(catalogue: catalogue)
        .modelContainer(container)
}
