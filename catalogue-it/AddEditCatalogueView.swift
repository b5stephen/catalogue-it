//
//  AddEditCatalogueView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AddEditCatalogueView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // If editing an existing catalogue, pass it in
    let catalogue: Catalogue?
    
    // Form state
    @State private var name: String = ""
    @State private var selectedIcon: String = "square.grid.2x2"
    @State private var selectedColor: Color = .blue
    @State private var fieldDefinitions: [FieldDefinitionDraft] = []
    @State private var showingIconPicker = false
    @State private var showingAddField = false
    
    var isEditing: Bool {
        catalogue != nil
    }
    
    init(catalogue: Catalogue? = nil) {
        self.catalogue = catalogue
    }
    
    var body: some View {
        NavigationStack {
            Form {
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
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .foregroundStyle(.primary)
                    
                    // Color Picker
                    ColorPicker("Color", selection: $selectedColor, supportsOpacity: false)
                }
                
                // MARK: - Field Definitions Section
                Section {
                    ForEach(fieldDefinitions) { field in
                        FieldDefinitionRow(field: field)
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
                    Text("Define what information you want to track for items in this catalogue.")
                }
            }
            .navigationTitle(isEditing ? "Edit Catalogue" : "New Catalogue")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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
        guard let catalogue = catalogue else {
            // Start with some common default fields for new catalogues
            fieldDefinitions = [
                FieldDefinitionDraft(name: "Name", fieldType: .text, sortOrder: 0)
            ]
            return
        }
        
        // Load existing catalogue data
        name = catalogue.name
        selectedIcon = catalogue.iconName
        selectedColor = Color(hex: catalogue.colorHex)
        fieldDefinitions = catalogue.fieldDefinitions
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { FieldDefinitionDraft(name: $0.name, fieldType: $0.fieldType, sortOrder: $0.sortOrder) }
    }
    
    private func saveCatalogue() {
        if let existingCatalogue = catalogue {
            // Update existing
            existingCatalogue.name = name
            existingCatalogue.iconName = selectedIcon
            existingCatalogue.colorHex = selectedColor.toHex()
            
            // Update field definitions (simplified - in production you'd handle this more carefully)
            // For now, we'll just clear and recreate them
            for field in existingCatalogue.fieldDefinitions {
                modelContext.delete(field)
            }
            
            for (index, draft) in fieldDefinitions.enumerated() {
                let field = FieldDefinition(name: draft.name, fieldType: draft.fieldType, sortOrder: index)
                field.catalogue = existingCatalogue
                modelContext.insert(field)
            }
        } else {
            // Create new
            let newCatalogue = Catalogue(name: name, iconName: selectedIcon, colorHex: selectedColor.toHex())
            modelContext.insert(newCatalogue)
            
            for (index, draft) in fieldDefinitions.enumerated() {
                let field = FieldDefinition(name: draft.name, fieldType: draft.fieldType, sortOrder: index)
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
            fieldDefinitions[index].sortOrder = index
        }
    }
}

// MARK: - Field Definition Row

struct FieldDefinitionRow: View {
    let field: FieldDefinitionDraft
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: field.fieldType.icon)
                .foregroundStyle(field.fieldType.color)
                .frame(width: 24)
            
            Text(field.name)
            
            Spacer()
            
            Text(field.fieldType.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Add Field View

struct AddFieldView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (FieldDefinitionDraft) -> Void
    
    @State private var fieldName: String = ""
    @State private var selectedType: FieldType = .text
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Field Details") {
                    TextField("Field Name", text: $fieldName)
#if os(iOS)
                        .textInputAutocapitalization(.words)
#endif
                    
                    Picker("Type", selection: $selectedType) {
                        ForEach(FieldType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }
                
                Section {
                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Image(systemName: selectedType.icon)
                                .foregroundStyle(selectedType.color)
                            Text(fieldName.isEmpty ? "Field Name" : fieldName)
                            Spacer()
                            Text(selectedType.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .navigationTitle("Add Field")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let field = FieldDefinitionDraft(name: fieldName, fieldType: selectedType, sortOrder: 0)
                        onAdd(field)
                        dismiss()
                    }
                    .disabled(fieldName.isEmpty)
                }
            }
        }
    }
}

// MARK: - Icon Picker View

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String
    
    // Curated list of good catalogue icons
    let iconCategories: [(String, [String])] = [
        ("Collections", ["square.grid.2x2", "square.grid.3x3", "rectangle.grid.3x2", "circle.grid.3x3"]),
        ("Objects", ["star.fill", "heart.fill", "bookmark.fill", "flag.fill", "tag.fill"]),
        ("Items", ["photo.fill", "book.fill", "magazine.fill", "newspaper.fill", "doc.fill"]),
        ("Sports", ["sportscourt.fill", "baseball.fill", "football.fill", "basketball.fill", "tennisball.fill"]),
        ("Entertainment", ["tv.fill", "music.note", "film.fill", "gamecontroller.fill", "guitars.fill"]),
        ("Nature", ["leaf.fill", "tree.fill", "globe.americas.fill", "cloud.fill", "moon.fill"]),
        ("Transportation", ["car.fill", "airplane", "train.side.front.car", "sailboat.fill", "bicycle"]),
        ("Food", ["cup.and.saucer.fill", "fork.knife", "wineglass.fill", "birthday.cake.fill", "takeoutbag.and.cup.and.straw.fill"]),
        ("Shopping", ["bag.fill", "cart.fill", "creditcard.fill", "giftcard.fill", "basket.fill"]),
        ("Other", ["hammer.fill", "wrench.fill", "paintbrush.fill", "scissors", "keyboard.fill"])
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(iconCategories, id: \.0) { category, icons in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category)
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                                ForEach(icons, id: \.self) { icon in
                                    Button {
                                        selectedIcon = icon
                                        dismiss()
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.title2)
                                            .frame(width: 60, height: 60)
                                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay {
                                                if selectedIcon == icon {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.accentColor, lineWidth: 2)
                                                }
                                            }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Choose Icon")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct FieldDefinitionDraft: Identifiable {
    let id = UUID()
    var name: String
    var fieldType: FieldType
    var sortOrder: Int
}

// MARK: - Extensions

extension FieldType {
    var color: Color {
        switch self {
        case .text: return .blue
        case .number: return .green
        case .date: return .orange
        case .boolean: return .purple
        }
    }
}

extension Color {
    func toHex() -> String {
#if canImport(UIKit)
        guard let components = UIColor(self).cgColor.components else { return "#007AFF" }
#elseif canImport(AppKit)
        guard let components = NSColor(self).cgColor.components else { return "#007AFF" }
#else
        return "#007AFF"
#endif
        
        let r = Int(components[0] * 255.0)
        let g = Int(components[1] * 255.0)
        let b = Int(components[2] * 255.0)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Preview

#Preview("New Catalogue") {
    AddEditCatalogueView()
        .modelContainer(for: Catalogue.self, inMemory: true)
}

#Preview("Icon Picker") {
    IconPickerView(selectedIcon: .constant("star.fill"))
}
