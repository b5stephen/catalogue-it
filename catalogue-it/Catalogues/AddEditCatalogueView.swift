//
//  AddEditCatalogueView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

struct AddEditCatalogueView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // If editing an existing catalogue, pass it in
    let catalogue: Catalogue?
    let nextPriority: Int

    // Form state
    @State private var name: String = ""
    @State private var selectedIcon: String = "square.grid.2x2"
    @State private var selectedColor: Color = .blue
    @State private var fieldDefinitions: [FieldDefinitionDraft] = []
    @State private var showingIconPicker = false
    @State private var showingAddField = false

    private var isEditing: Bool {
        catalogue != nil
    }

    init(catalogue: Catalogue? = nil, nextPriority: Int = 0) {
        self.catalogue = catalogue
        self.nextPriority = nextPriority
    }

    var body: some View {
        NavigationStack {
            Form {
                // editMode is set to .active so drag handles appear permanently on field rows
                // MARK: - Basic Info Section
                Section("Catalogue Details") {
                    TextField("Name", text: $name)
#if os(iOS)
                        .textInputAutocapitalization(.words)
#endif

                    // Icon Picker
                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack {
                            Text("Icon")
                            Spacer()
                            Image(systemName: selectedIcon)
                                .font(.title2)
                                .foregroundStyle(selectedColor)
                                .frame(width: 32, height: 32)
                                .background(selectedColor.opacity(0.15))
                                .clipShape(.rect(cornerRadius: 6))
                        }
                    }
                    .foregroundStyle(.primary)

                    // Color Picker
                    ColorPicker("Color", selection: $selectedColor, supportsOpacity: false)
                }

                // MARK: - Field Definitions Section
                Section {
                    ForEach($fieldDefinitions) { $field in
                        FieldDefinitionRow(field: $field)
                    }
                    .onDelete(perform: deleteField)
                    .onMove(perform: moveField)

                    Button {
                        showingAddField = true
                    } label: {
                        Label("Add Field", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Custom Fields")
                } footer: {
                    Text("Drag fields to reorder. The first field is used as each item's display name.")
                }
            }
#if os(iOS)
            .environment(\.editMode, .constant(.active))
#endif
            .navigationTitle(isEditing ? "Edit Catalogue" : "New Catalogue")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        saveCatalogue()
                    }
                    .disabled(name.isEmpty || fieldDefinitions.isEmpty)
                }

#if os(iOS)
                ToolbarItem(placement: .principal) {
                    // Show a preview of icon + color
                    Image(systemName: selectedIcon)
                        .foregroundStyle(selectedColor)
                }
#endif
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
            .sheet(isPresented: $showingAddField) {
                AddFieldView { field in
                    fieldDefinitions.append(field)
                }
            }
            .onAppear {
                loadCatalogueData()
            }
        }
    }

    // MARK: - Actions

    private func loadCatalogueData() {
        guard let catalogue else {
            // Start with some common default fields for new catalogues
            fieldDefinitions = [
                FieldDefinitionDraft(existingDefinition: nil, name: "Name", fieldType: .text, priority: 0)
            ]
            return
        }

        // Load existing catalogue data
        name = catalogue.name
        selectedIcon = catalogue.iconName
        selectedColor = Color(hex: catalogue.colorHex)
        fieldDefinitions = catalogue.fieldDefinitions
            .sorted { $0.priority < $1.priority }
            .map { FieldDefinitionDraft(existingDefinition: $0, name: $0.name, fieldType: $0.fieldType, priority: $0.priority, precision: $0.precision) }
    }

    private func saveCatalogue() {
        if let existingCatalogue = catalogue {
            // Update existing
            existingCatalogue.name = name
            existingCatalogue.iconName = selectedIcon
            existingCatalogue.colorHex = selectedColor.toHex()

            // Delete fields that were removed
            let retained = Set(fieldDefinitions.compactMap(\.existingDefinition?.persistentModelID))
            for field in existingCatalogue.fieldDefinitions where !retained.contains(field.persistentModelID) {
                modelContext.delete(field)
            }

            // Update existing fields in-place / insert new fields
            for (index, draft) in fieldDefinitions.enumerated() {
                if let existing = draft.existingDefinition {
                    existing.name = draft.name  // rename applied here — no cascade needed
                    existing.priority = index
                    existing.precision = draft.precision
                } else {
                    let field = FieldDefinition(name: draft.name, fieldType: draft.fieldType, priority: index)
                    field.precision = draft.precision
                    field.catalogue = existingCatalogue
                    modelContext.insert(field)
                }
            }
        } else {
            // Create new
            let newCatalogue = Catalogue(name: name, iconName: selectedIcon, colorHex: selectedColor.toHex(), priority: nextPriority)
            modelContext.insert(newCatalogue)

            for (index, draft) in fieldDefinitions.enumerated() {
                let field = FieldDefinition(name: draft.name, fieldType: draft.fieldType, priority: index)
                field.precision = draft.precision
                field.catalogue = newCatalogue
                modelContext.insert(field)
            }
        }

        dismiss()
    }

    private func deleteField(at offsets: IndexSet) {
        fieldDefinitions.remove(atOffsets: offsets)
    }

    private func moveField(from source: IndexSet, to destination: Int) {
        fieldDefinitions.move(fromOffsets: source, toOffset: destination)
        // Update sort order
        for (index, _) in fieldDefinitions.enumerated() {
            fieldDefinitions[index].priority = index
        }
    }
}

// MARK: - Preview

#Preview("New Catalogue") {
    AddEditCatalogueView()
        .modelContainer(for: Catalogue.self, inMemory: true)
}
