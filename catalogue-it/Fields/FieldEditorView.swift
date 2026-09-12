//
//  FieldEditorView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Field Editor View

/// The one form for defining a field, used both when adding a new field and when editing an
/// existing one. Editing shows exactly the same controls as adding, with two differences:
/// the type picker is locked (an existing field's stored values are typed, so changing it
/// would strand them), and option-list renames and deletions are recorded on the draft so
/// `AddEditCatalogueView` can cascade them to `FieldValue` records on save.
struct FieldEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// Names of the *other* fields in the catalogue. When editing, the field's own name is
    /// excluded by the caller so keeping it isn't flagged as a duplicate.
    let existingNames: [String]
    private let isEditing: Bool
    let onSave: (FieldDefinitionDraft) -> Void

    @State private var draft: FieldDefinitionDraft
    @State private var newOptionText: String = ""
    @State private var renamingOption: String? = nil
    @State private var renameText: String = ""

    /// Adding: starts from an empty Text field.
    init(existingNames: [String] = [], onAdd: @escaping (FieldDefinitionDraft) -> Void) {
        self.existingNames = existingNames
        self.isEditing = false
        self.onSave = onAdd
        _draft = State(initialValue: FieldDefinitionDraft(name: "", fieldType: .text, priority: 0))
    }

    /// Editing: starts from the field as it stands, and hands back the edited draft.
    init(editing field: FieldDefinitionDraft, existingNames: [String] = [], onSave: @escaping (FieldDefinitionDraft) -> Void) {
        self.existingNames = existingNames
        self.isEditing = true
        self.onSave = onSave
        _draft = State(initialValue: field)
    }

    // Trimmed candidate for the new option being typed
    private var trimmedNew: String { newOptionText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddOption: Bool { !trimmedNew.isEmpty && !draft.optionListOptions.options.contains(trimmedNew) }

    private var trimmedFieldName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicateName: Bool {
        !trimmedFieldName.isEmpty && existingNames.contains { $0.localizedCaseInsensitiveCompare(trimmedFieldName) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Field Name", text: $draft.name)
#if os(iOS)
                        .textInputAutocapitalization(.words)
#endif
                        .accessibilityIdentifier("add-field-name")

                    if isDuplicateName {
                        Text("A field with this name already exists.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker("Type", selection: $draft.fieldType) {
                        ForEach(FieldType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .disabled(isEditing)
                } header: {
                    Text("Field Details")
                } footer: {
                    if isEditing {
                        Text("A field's type can't be changed once it holds data. Delete the field and add a new one to change it.")
                    }
                }

                if draft.fieldType == .number {
                    Section("Number Options") {
                        Picker("Format", selection: $draft.numberOptions.format) {
                            ForEach(NumberFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Decimal Places", selection: $draft.numberOptions.precision) {
                            Text("0 (Whole numbers)").tag(0)
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("4").tag(4)
                        }

                        Toggle("Thousands Separator", isOn: $draft.numberOptions.usesGroupingSeparator)
                    }
                }

                if draft.fieldType == .optionList {
                    Section {
                        ForEach(draft.optionListOptions.options.sorted(), id: \.self) { option in
                            HStack {
                                Text(option)
                                Spacer()
                                if option == draft.optionListOptions.defaultValue {
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
                                    deleteOption(option)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                draft.optionListOptions.defaultValue = (draft.optionListOptions.defaultValue == option) ? nil : option
                            }
                        }

                        HStack {
                            TextField("New option", text: $newOptionText)
#if os(iOS)
                                .textInputAutocapitalization(.words)
#endif
                            Button {
                                draft.optionListOptions.options.append(trimmedNew)
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
                if draft.fieldType == .boolean {
                    BooleanOptionsSection(options: $draft.booleanOptions)
                }

                // A working sample of the field as configured so far — the same controls the
                // item form will show, re-seeded whenever the type or its options change.
                FieldPreviewSection(
                    name: draft.name,
                    fieldType: draft.fieldType,
                    numberOptions: draft.numberOptions,
                    optionListOptions: draft.optionListOptions,
                    booleanOptions: draft.booleanOptions,
                    displayRole: draft.displayRole
                )
                // Switching type resets the sample value along with the options it belongs to.
                .id(draft.fieldType)
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
                        guard !trimmed.isEmpty, !draft.optionListOptions.options.contains(trimmed) || trimmed == old else { return }
                        renameOption(old, to: trimmed)
                        renamingOption = nil
                    }
                }
            } message: {
                Text("Enter a new name for \"\(renamingOption ?? "")\".")
            }
            .onChange(of: draft.numberOptions.format) {
                if draft.numberOptions.format == .currency { draft.numberOptions.precision = 2 }
            }
            .onChange(of: draft.fieldType) {
                // Only reachable while adding — the picker is locked when editing.
                draft.numberOptions = NumberOptions()
                draft.optionListOptions = OptionListOptions()
                draft.booleanOptions = BooleanOptions()
                newOptionText = ""
                renamingOption = nil
            }
            .navigationTitle(isEditing ? "Edit Field" : "Add Field")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Done" : "Add") {
                        var edited = draft
                        edited.name = trimmedFieldName
                        // Dropping below the two-option minimum makes a tab bar impossible;
                        // give up the role here so the Options section stops offering this
                        // field as the status field, rather than silently discarding it.
                        if edited.displayRole == .statusTabs,
                           edited.fieldType == .optionList,
                           edited.optionListOptions.options.count < FieldDefinitionValidation.minimumStatusOptions {
                            edited.displayRole = .none
                        }
                        onSave(edited)
                        dismiss()
                    }
                    .disabled(trimmedFieldName.isEmpty || isDuplicateName)
                }
            }
        }
    }

    // MARK: - Option Edits

    /// Renames an option, recording the change for the save-time cascade to stored values.
    /// Chains collapse: renaming A→B then B→C is recorded as A→C, so the cascade only ever
    /// looks for names that are actually on disk.
    private func renameOption(_ old: String, to new: String) {
        if let index = draft.optionListOptions.options.firstIndex(of: old) {
            draft.optionListOptions.options[index] = new
        }
        if draft.optionListOptions.defaultValue == old {
            draft.optionListOptions.defaultValue = new
        }
        guard new != old, draft.existingDefinition != nil else { return }
        if let originalName = draft.pendingOptionRenames.first(where: { $0.value == old })?.key {
            draft.pendingOptionRenames[originalName] = new
        } else {
            draft.pendingOptionRenames[old] = new
        }
    }

    private func deleteOption(_ option: String) {
        draft.optionListOptions.options.removeAll { $0 == option }
        if draft.optionListOptions.defaultValue == option {
            draft.optionListOptions.defaultValue = nil
        }
        guard draft.existingDefinition != nil else { return }
        // A pending rename pointing at this option is simply dropped — the stored value is
        // still under its original name, and the deletion below clears it by that name.
        if let originalName = draft.pendingOptionRenames.first(where: { $0.value == option })?.key {
            draft.pendingOptionRenames.removeValue(forKey: originalName)
            draft.pendingOptionDeletions.insert(originalName)
        } else {
            draft.pendingOptionDeletions.insert(option)
        }
    }
}
