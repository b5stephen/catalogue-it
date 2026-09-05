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
    let existingNames: [String]
    let onAdd: (FieldDefinitionDraft) -> Void

    init(existingNames: [String] = [], onAdd: @escaping (FieldDefinitionDraft) -> Void) {
        self.existingNames = existingNames
        self.onAdd = onAdd
    }

    @State private var fieldName: String = ""
    @State private var selectedType: FieldType = .text
    @State private var booleanOptions: BooleanOptions = BooleanOptions()
    @State private var numberOptions: NumberOptions = NumberOptions()
    @State private var optionListOptions: OptionListOptions = OptionListOptions()
    @State private var newOptionText: String = ""
    @State private var renamingOption: String? = nil
    @State private var renameText: String = ""

    // Trimmed candidate for the new option being typed
    private var trimmedNew: String { newOptionText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddOption: Bool { !trimmedNew.isEmpty && !optionListOptions.options.contains(trimmedNew) }

    private var trimmedFieldName: String { fieldName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicateName: Bool {
        !trimmedFieldName.isEmpty && existingNames.contains { $0.localizedCaseInsensitiveCompare(trimmedFieldName) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Field Details") {
                    TextField("Field Name", text: $fieldName)
#if os(iOS)
                        .textInputAutocapitalization(.words)
#endif
                        .accessibilityIdentifier("add-field-name")

                    if isDuplicateName {
                        Text("A field with this name already exists.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker("Type", selection: $selectedType) {
                        ForEach(FieldType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }

                if selectedType == .number {
                    Section("Number Options") {
                        Picker("Format", selection: $numberOptions.format) {
                            ForEach(NumberFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Decimal Places", selection: $numberOptions.precision) {
                            Text("0 (Whole numbers)").tag(0)
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("4").tag(4)
                        }
                    }
                }

                if selectedType == .optionList {
                    Section {
                        ForEach(optionListOptions.options.sorted(), id: \.self) { option in
                            HStack {
                                Text(option)
                                Spacer()
                                if option == optionListOptions.defaultValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                                Button {
                                    renamingOption = option
                                    renameText = option
                                } label: {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                Button(role: .destructive) {
                                    optionListOptions.options.removeAll { $0 == option }
                                    if optionListOptions.defaultValue == option {
                                        optionListOptions.defaultValue = nil
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                optionListOptions.defaultValue = (optionListOptions.defaultValue == option) ? nil : option
                            }
                        }

                        HStack {
                            TextField("New option", text: $newOptionText)
#if os(iOS)
                                .textInputAutocapitalization(.words)
#endif
                            Button {
                                optionListOptions.options.append(trimmedNew)
                                newOptionText = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAddOption)
                        }
                    } header: {
                        Text("Options")
                    } footer: {
                        Text("Tap an option to set it as the default. Tap again to clear.")
                    }
                }

                // Peer of the type-specific option sections above. Which fields drive the
                // tab bar or a filter toggle is decided in the catalogue's Options section,
                // once the field exists — this form only configures the field itself.
                if selectedType == .boolean {
                    BooleanOptionsSection(options: $booleanOptions)
                }

                // A working sample of the field as configured so far — the same controls the
                // item form will show, re-seeded whenever the type or its options change.
                FieldPreviewSection(
                    name: fieldName,
                    fieldType: selectedType,
                    numberOptions: numberOptions,
                    optionListOptions: optionListOptions,
                    booleanOptions: booleanOptions
                )
                // Switching type resets the sample value along with the options it belongs to.
                // Display roles are assigned in the catalogue's Options section once the field
                // exists, so a field being added always previews as an ordinary one.
                .id(selectedType)
            }
            .alert("Rename Option", isPresented: Binding(get: { renamingOption != nil }, set: { if !$0 { renamingOption = nil } })) {
                TextField("Option name", text: $renameText)
#if os(iOS)
                    .textInputAutocapitalization(.words)
#endif
                Button("Cancel", role: .cancel) { renamingOption = nil }
                Button("Rename") {
                    if let old = renamingOption {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, !optionListOptions.options.contains(trimmed) || trimmed == old else { return }
                        if let idx = optionListOptions.options.firstIndex(of: old) { optionListOptions.options[idx] = trimmed }
                        if optionListOptions.defaultValue == old { optionListOptions.defaultValue = trimmed }
                        renamingOption = nil
                    }
                }
            } message: {
                Text("Enter a new name for \"\(renamingOption ?? "")\".")
            }
            .onChange(of: numberOptions.format) {
                if numberOptions.format == .currency { numberOptions.precision = 2 }
            }
            .onChange(of: selectedType) {
                numberOptions = NumberOptions()
                optionListOptions = OptionListOptions()
                booleanOptions = BooleanOptions()
                newOptionText = ""
                renamingOption = nil
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
                        var field = FieldDefinitionDraft(name: trimmedFieldName, fieldType: selectedType, priority: 0)
                        field.numberOptions = numberOptions
                        field.optionListOptions = optionListOptions
                        field.booleanOptions = booleanOptions
                        onAdd(field)
                        dismiss()
                    }
                    .disabled(trimmedFieldName.isEmpty || isDuplicateName)
                }
            }
        }
    }
}
