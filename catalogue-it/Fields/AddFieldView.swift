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
    /// Name of the field that currently drives the tab bar, if any. Only one is allowed per
    /// catalogue, so choosing `.statusTabs` here will take the role from that field — the
    /// display section says so rather than the caller silently resolving it later.
    let currentStatusFieldName: String?
    /// Catalogue-level "All" tab setting, editable here because adding a status field is the
    /// moment the setting first becomes meaningful.
    @Binding var showAllTab: Bool
    let onAdd: (FieldDefinitionDraft) -> Void

    init(
        existingNames: [String] = [],
        currentStatusFieldName: String? = nil,
        showAllTab: Binding<Bool> = .constant(false),
        onAdd: @escaping (FieldDefinitionDraft) -> Void
    ) {
        self.existingNames = existingNames
        self.currentStatusFieldName = currentStatusFieldName
        self._showAllTab = showAllTab
        self.onAdd = onAdd
    }

    @State private var fieldName: String = ""
    @State private var selectedType: FieldType = .text
    @State private var displayRole: DisplayRole = .none
    @State private var booleanOptions: BooleanOptions = BooleanOptions()
    @State private var numberOptions: NumberOptions = NumberOptions()
    @State private var optionListOptions: OptionListOptions = OptionListOptions()
    @State private var newOptionText: String = ""
    @State private var renamingOption: String? = nil
    @State private var renameText: String = ""

    // Trimmed candidate for the new option being typed
    private var trimmedNew: String { newOptionText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddOption: Bool { !trimmedNew.isEmpty && !optionListOptions.options.contains(trimmedNew) }

    /// Owned/Wishlist reproduces the app's previous built-in behaviour as a starting point,
    /// so the most common case needs no configuration at all.
    private static let defaultStatusOptions = OptionListOptions(
        options: ["Owned", "Wishlist"],
        defaultValue: "Owned"
    )

    /// A tab bar backed by an option list needs 2+ options, so "Add" stays disabled until
    /// the user has defined enough — the same rule `FieldDefinitionValidation` enforces on save.
    private var meetsRoleRequirements: Bool {
        FieldDefinitionValidation.supports(
            role: displayRole,
            fieldType: selectedType,
            optionCount: optionListOptions.options.count
        )
    }

    /// Fills in the settings below for a status tracker. A shortcut, not a mode — everything
    /// it sets stays editable, and the same result is reachable by hand from any option-list
    /// or boolean field.
    private func applyStatusTrackerPreset() {
        selectedType = .optionList
        optionListOptions = Self.defaultStatusOptions
        displayRole = .statusTabs
        if trimmedFieldName.isEmpty { fieldName = "Status" }
    }

    /// Shortcut for the favourite/star case: a boolean carrying a filter toggle.
    private func applyFavouritePreset() {
        selectedType = .boolean
        booleanOptions = BooleanOptions()
        displayRole = .flagFilter
        if trimmedFieldName.isEmpty { fieldName = "Favourite" }
    }

    private var trimmedFieldName: String { fieldName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicateName: Bool {
        !trimmedFieldName.isEmpty && existingNames.contains { $0.localizedCaseInsensitiveCompare(trimmedFieldName) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Actions rather than a persistent selection: these fill in the settings
                // below and then get out of the way. A stored "kind" would go stale the
                // moment the user adjusted the type or role by hand.
                Section {
                    Button {
                        applyStatusTrackerPreset()
                    } label: {
                        Label("Status Tracker", systemImage: "square.grid.3x1.below.line.grid.1x2")
                    }
                    Button {
                        applyFavouritePreset()
                    } label: {
                        Label("Favourite / Star", systemImage: "star")
                    }
                } header: {
                    Text("Quick Setup")
                } footer: {
                    Text("Fills in the settings below for the two most common cases. Everything stays editable afterwards.")
                }

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

                    // Switching to Yes/No or Option List keeps whatever role is set, which is
                    // what makes "any boolean or option-list field can carry a role" true.
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
                        if displayRole == .statusTabs {
                            Text("Each option becomes a tab in the item list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

                // Peer of the type-specific option sections above: appears for any type that
                // can carry a display role, whether or not a quick-setup shortcut was used.
                FieldDisplayOptionsSection(
                    fieldType: selectedType,
                    fieldName: trimmedFieldName,
                    optionCount: optionListOptions.options.count,
                    otherStatusFieldName: currentStatusFieldName,
                    displayRole: $displayRole,
                    booleanOptions: $booleanOptions,
                    showAllTab: $showAllTab
                )

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
                // Switching back to an option list while a tab bar is configured must restore
                // starting options — otherwise the user lands on an empty list with Add disabled.
                if displayRole == .statusTabs && selectedType == .optionList {
                    optionListOptions = Self.defaultStatusOptions
                }
                // A role the new type can't carry is dropped rather than silently reset on save.
                if !FieldDefinitionValidation.supports(
                    role: displayRole,
                    fieldType: selectedType,
                    optionCount: optionListOptions.options.count
                ) {
                    displayRole = .none
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
                        var field = FieldDefinitionDraft(name: trimmedFieldName, fieldType: selectedType, priority: 0)
                        field.displayRole = displayRole
                        field.numberOptions = numberOptions
                        field.optionListOptions = optionListOptions
                        field.booleanOptions = booleanOptions
                        onAdd(field)
                        dismiss()
                    }
                    .disabled(trimmedFieldName.isEmpty || isDuplicateName || !meetsRoleRequirements)
                }
            }
        }
    }
}
