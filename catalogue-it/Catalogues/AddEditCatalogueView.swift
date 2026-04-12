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

    // Field deletion confirmation
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var pendingDeleteFieldName = ""
    @State private var pendingDeleteItemCount = 0
    @State private var showingFieldDeleteConfirmation = false

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
                        .accessibilityIdentifier("catalogue-name-field")

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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fieldDefinitions.isEmpty)
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
            .confirmationDialog(
                "Delete \"\(pendingDeleteFieldName)\"?",
                isPresented: $showingFieldDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Field", role: .destructive) {
                    if let offsets = pendingDeleteOffsets {
                        fieldDefinitions.remove(atOffsets: offsets)
                    }
                    pendingDeleteOffsets = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteOffsets = nil
                }
            } message: {
                let n = pendingDeleteItemCount
                Text("This field contains data in \(n) item\(n == 1 ? "" : "s"). Deleting it will permanently remove that data when you save. You can still Cancel to keep the field.")
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
        selectedColor = catalogue.color
        fieldDefinitions = catalogue.fieldDefinitions
            .sorted { $0.priority < $1.priority }
            .map { FieldDefinitionDraft(existingDefinition: $0, name: $0.name, fieldType: $0.fieldType, priority: $0.priority, numberOptions: $0.numberOptions ?? NumberOptions(), optionListOptions: $0.optionListOptions ?? OptionListOptions()) }
    }

    private func saveCatalogue() {
        if let existingCatalogue = catalogue {
            // Update existing
            existingCatalogue.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existingCatalogue.iconName = selectedIcon
            existingCatalogue.colorHex = selectedColor.toHex()

            // Delete fields that were removed
            let retained = Set(fieldDefinitions.compactMap(\.existingDefinition?.persistentModelID))
            for field in existingCatalogue.fieldDefinitions where !retained.contains(field.persistentModelID) {
                let fieldID = field.persistentModelID
                try? modelContext.delete(model: FieldValue.self,
                    where: #Predicate { $0.fieldDefinition?.persistentModelID == fieldID })
                modelContext.delete(field)
            }

            // Update existing fields in-place / insert new fields
            for (index, draft) in fieldDefinitions.enumerated() {
                if let existing = draft.existingDefinition {
                    existing.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)  // rename applied here — no cascade needed
                    existing.priority = index
                    existing.numberOptions = draft.numberOptions
                    existing.optionListOptions = draft.optionListOptions
                } else {
                    let field = FieldDefinition(name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), fieldType: draft.fieldType, priority: index)
                    field.numberOptions = draft.numberOptions
                    field.optionListOptions = draft.optionListOptions
                    field.catalogue = existingCatalogue
                    modelContext.insert(field)
                }
            }
        } else {
            // Create new
            let newCatalogue = Catalogue(name: name.trimmingCharacters(in: .whitespacesAndNewlines), iconName: selectedIcon, colorHex: selectedColor.toHex(), priority: nextPriority)
            modelContext.insert(newCatalogue)

            for (index, draft) in fieldDefinitions.enumerated() {
                let field = FieldDefinition(name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), fieldType: draft.fieldType, priority: index)
                field.numberOptions = draft.numberOptions
                field.optionListOptions = draft.optionListOptions
                field.catalogue = newCatalogue
                modelContext.insert(field)
            }
        }

        dismiss()
    }

    private func deleteField(at offsets: IndexSet) {
        let affectedFields = offsets.map { fieldDefinitions[$0] }
        let totalDataCount = affectedFields.reduce(0) { $0 + itemDataCount(for: $1) }

        if totalDataCount > 0 {
            pendingDeleteOffsets = offsets
            pendingDeleteFieldName = affectedFields.first?.name ?? ""
            pendingDeleteItemCount = totalDataCount
            showingFieldDeleteConfirmation = true
        } else {
            fieldDefinitions.remove(atOffsets: offsets)
        }
    }

    private func itemDataCount(for draft: FieldDefinitionDraft) -> Int {
        guard let field = draft.existingDefinition else { return 0 }
        return field.fieldValues.count { fv in
            switch fv.fieldType {
            case .text, .optionList: return fv.textValue != nil
            case .number:            return fv.numberValue != nil
            case .date:              return fv.dateValue != nil
            case .boolean:           return fv.boolValue == true
            }
        }
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
