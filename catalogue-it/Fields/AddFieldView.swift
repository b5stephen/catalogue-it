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
    @State private var precision: Int = 0

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

                if selectedType == .number || selectedType == .currency {
                    Section("Decimal Places") {
                        Picker("Decimal Places", selection: $precision) {
                            Text("0 (Whole numbers)").tag(0)
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("4").tag(4)
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
            .onChange(of: selectedType) { precision = selectedType == .currency ? 2 : 0 }
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
                        var field = FieldDefinitionDraft(name: fieldName, fieldType: selectedType, priority: 0)
                        field.precision = precision
                        onAdd(field)
                        dismiss()
                    }
                    .disabled(fieldName.isEmpty)
                }
            }
        }
    }
}
