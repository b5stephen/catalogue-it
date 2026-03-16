//
//  AddFieldView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

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
                            Text(fieldName.isEmpty ? "Field Name" : fieldName)
                            Spacer()
                            Text(selectedType.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 8))
                    }
                }
            }
            .navigationTitle("Add Field")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
