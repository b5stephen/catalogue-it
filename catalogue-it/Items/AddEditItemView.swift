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

    @State private var sortedDefs: [FieldDefinition] = []
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
                    ForEach(fieldDrafts.indices, id: \.self) { index in
                        FieldInputView(label: sortedDefs[index].name, draft: $fieldDrafts[index])
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
        sortedDefs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }

        if let item = existingItem {
            // Edit mode: populate from existing item
            fieldDrafts = sortedDefs.map { def in
                var draft = FieldValueDraft(
                    fieldDefinition: def,
                    fieldType: def.fieldType
                )
                if let fv = item.value(for: def) {
                    switch def.fieldType {
                    case .text:
                        draft.textValue = fv.textValue ?? ""
                    case .number:
                        draft.numberValue = fv.numberValue
                    case .date:
                        draft.dateValue = fv.dateValue
                    case .boolean:
                        draft.boolValue = fv.boolValue ?? false
                    }
                }
                return draft
            }

            photoDrafts = item.photos
                .sorted { $0.priority < $1.priority }
                .enumerated()
                .map { index, photo in
                    PhotoDraft(
                        imageData: photo.imageData,
                        caption: photo.caption ?? "",
                        priority: index
                    )
                }

            isWishlist = item.isWishlist
            notes = item.notes ?? ""
        } else {
            // Create mode: blank drafts
            fieldDrafts = sortedDefs.map { def in
                FieldValueDraft(fieldDefinition: def, fieldType: def.fieldType)
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
            let fv = FieldValue(fieldDefinition: draft.fieldDefinition, fieldType: draft.fieldType)
            switch draft.fieldType {
            case .text:
                fv.textValue = draft.textValue.isEmpty ? nil : draft.textValue
            case .number:
                fv.numberValue = draft.numberValue
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
                priority: draft.priority,
                caption: draft.caption.isEmpty ? nil : draft.caption
            )
            photo.item = targetItem
            modelContext.insert(photo)
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview("New Item") {
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

    return AddEditItemView(catalogue: catalogue)
        .modelContainer(container)
}
