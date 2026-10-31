//
//  FieldEditorView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Field Editor View

/// Editing locks the type, since stored values are typed, and records option renames
/// and deletions on the draft for `AddEditCatalogueView` to cascade on save.
struct FieldEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// The *other* fields' names; the caller excludes this field's own.
    let existingNames: [String]
    private let isEditing: Bool
    let onSave: (FieldDefinitionDraft) -> Void

    @State private var draft: FieldDefinitionDraft
    private let initialDraft: FieldDefinitionDraft
    @State private var newOptionText: String = ""
    @FocusState private var isAddOptionFocused: Bool

    init(existingNames: [String] = [], onAdd: @escaping (FieldDefinitionDraft) -> Void) {
        self.existingNames = existingNames
        self.isEditing = false
        self.onSave = onAdd
        let empty = FieldDefinitionDraft(name: "", fieldType: .text, priority: 0)
        self.initialDraft = empty
        _draft = State(initialValue: empty)
    }

    init(editing field: FieldDefinitionDraft, existingNames: [String] = [], onSave: @escaping (FieldDefinitionDraft) -> Void) {
        self.existingNames = existingNames
        self.isEditing = true
        self.onSave = onSave
        self.initialDraft = field
        _draft = State(initialValue: field)
    }

    /// An option typed but not yet added counts too — it would be lost just the same.
    private var hasChanges: Bool {
        !draft.hasSameContent(as: initialDraft) || !trimmedNew.isEmpty
    }

    private var trimmedNew: String { newOptionText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var sortedOptions: [String] { draft.optionListOptions.options.sorted() }

    private var trimmedFieldName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicateName: Bool {
        !trimmedFieldName.isEmpty && existingNames.contains { $0.localizedCaseInsensitiveCompare(trimmedFieldName) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isEditing {
                    previewSection
                }

                nameSection

                if !isEditing {
                    typeSection
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
                    optionsSection
                    if !draft.optionListOptions.options.isEmpty {
                        defaultOptionSection
                    }
                }

                if draft.fieldType == .boolean {
                    BooleanOptionsSection(draft: $draft)
                }

                if !isEditing {
                    previewSection
                }
            }
            .onChange(of: draft.numberOptions.format) {
                if draft.numberOptions.format == .currency { draft.numberOptions.precision = 2 }
            }
            .onChange(of: draft.fieldType) {
                // Only reachable while adding — the type is locked when editing.
                draft.numberOptions = NumberOptions()
                draft.optionListOptions = OptionListOptions()
                draft.booleanOptions = BooleanOptions()
                draft.displayRole = .none
                newOptionText = ""
            }
            .navigationTitle(isEditing ? "Edit Field" : "Add Field")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Done" : "Add", systemImage: "checkmark") {
                        var edited = draft
                        edited.name = trimmedFieldName
                        // Below the option minimum a tab bar is impossible.
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
        // A swipe-down or tap outside would silently drop edits.
        .interactiveDismissDisabled(hasChanges)
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Field Name", text: $draft.name)
                .font(.system(.title3, weight: .semibold))
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
                .accessibilityIdentifier("add-field-name")

            if isDuplicateName {
                Text("A field with this name already exists.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isEditing {
                lockedTypeRow
            }
        } footer: {
            if isEditing {
                Text("A field's type can't be changed once it holds data.")
            }
        }
    }

    private var lockedTypeRow: some View {
        HStack(spacing: 8) {
            Text("Type")
            Spacer()
            FieldTypeTile(draft.fieldType)
            Text(draft.fieldType.rawValue)
            Image(systemName: "lock.fill")
                .imageScale(.small)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Type, \(draft.fieldType.rawValue), can't be changed")
    }

    private var typeSection: some View {
        Section {
            ForEach(FieldType.allCases, id: \.self) { type in
                Button {
                    draft.fieldType = type
                } label: {
                    HStack(spacing: 12) {
                        FieldTypeTile(type)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.rawValue)
                                .foregroundStyle(.primary)
                            Text(type.pickerDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if draft.fieldType == type {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(type.rawValue)
                .accessibilityValue(type.pickerDescription)
                .accessibilityAddTraits(draft.fieldType == type ? .isSelected : [])
                .accessibilityIdentifier("field-type-\(type.rawValue)")
            }
        } header: {
            Text("Type")
        } footer: {
            Text("The type can't be changed once the field is saved.")
        }
    }

    private var previewSection: some View {
        FieldPreviewSection(
            name: draft.name,
            fieldType: draft.fieldType,
            numberOptions: draft.numberOptions,
            optionListOptions: draft.optionListOptions,
            booleanOptions: draft.booleanOptions,
            displayRole: draft.displayRole
        )
        .id(draft.fieldType)
    }

    // MARK: - Option List

    private var optionsSection: some View {
        Section {
            ForEach(sortedOptions, id: \.self) { option in
                OptionNameRow(
                    option: option,
                    isDefault: option == draft.optionListOptions.defaultValue
                ) { newName in
                    commitRename(of: option, to: newName)
                }
            }
            .onDelete { offsets in
                let doomed = offsets.map { sortedOptions[$0] }
                for option in doomed { draft.deleteOption(option) }
            }

            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.white, .green)
                    .accessibilityHidden(true)
                TextField("Add Option", text: $newOptionText)
                    .focused($isAddOptionFocused)
                    .submitLabel(.next)
                    .onSubmit(addOption)
#if os(iOS)
                    .textInputAutocapitalization(.words)
#endif
                    .accessibilityIdentifier("add-option-field")
            }
        } header: {
            Text("Options")
        } footer: {
            Text(optionsFooter)
        }
    }

    private var optionsFooter: LocalizedStringKey {
        draft.existingDefinition == nil
            ? "Press Return to add the next one. Swipe an option to delete it."
            : "Press Return to add the next one. Renaming an option updates every item that uses it. Swipe an option to delete it."
    }

    private var defaultOptionSection: some View {
        Section {
            Picker("New Items Start As", selection: $draft.optionListOptions.defaultValue) {
                Text("None").tag(String?.none)
                ForEach(sortedOptions, id: \.self) { option in
                    Text(option).tag(String?.some(option))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func addOption() {
        let option = trimmedNew
        if !option.isEmpty, !draft.optionListOptions.options.contains(option) {
            draft.optionListOptions.options.append(option)
            newOptionText = ""
        }
        // Submitting dismisses the keyboard, so focus is asked for again once that settles.
        Task { isAddOptionFocused = true }
    }

    /// An empty or duplicate name is dropped; the row reverts itself.
    private func commitRename(of old: String, to new: String) {
        guard !new.isEmpty, new != old, !draft.optionListOptions.options.contains(new) else { return }
        draft.renameOption(old, to: new)
    }
}

// MARK: - Option Name Row

/// Edits a local copy of the name, so the sorted list doesn't reshuffle while typing.
private struct OptionNameRow: View {
    let option: String
    let isDefault: Bool
    let onCommit: (String) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(option: String, isDefault: Bool, onCommit: @escaping (String) -> Void) {
        self.option = option
        self.isDefault = isDefault
        self.onCommit = onCommit
        _text = State(initialValue: option)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Option", text: $text)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(commit)
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
            if isDefault {
                FieldBadge(title: String(localized: "Default"), systemImage: nil, tint: .secondary)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A rejected name leaves this row alive, so it reverts here.
        text = option
        onCommit(trimmed)
    }
}
