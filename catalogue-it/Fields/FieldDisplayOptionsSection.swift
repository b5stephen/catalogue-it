//
//  FieldDisplayOptionsSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Display Options Section

/// Form sections controlling how a field is surfaced in the item list.
///
/// Peer of the existing "Number Options" and "Options" sections: it appears for any field
/// whose type can carry a display role — `.boolean` or `.optionList` — so a role can be set
/// on any eligible field, not only on one created through a preset.
///
/// Shared between the add-field form and the per-field editing sheet so both offer exactly
/// the same capability; a field's role must be as changeable later as it was at creation.
struct FieldDisplayOptionsSection: View {
    let fieldType: FieldType
    let fieldName: String
    /// Number of options currently defined, for the `.optionList` minimum check.
    let optionCount: Int
    /// Name of a *different* field that currently drives the tab bar, if any. Used to warn
    /// that claiming the role here will take it away from that field.
    let otherStatusFieldName: String?

    @Binding var displayRole: DisplayRole
    @Binding var booleanOptions: BooleanOptions
    /// Catalogue-level, but only meaningful alongside a status field, so it is configured
    /// here with the role that gives it meaning rather than in a section of its own.
    @Binding var showAllTab: Bool

    @State private var showingIconPicker = false

    /// Mirrors `FieldDefinition.flagIconName` / `.flagColor` for a field that may not exist
    /// yet — the add-field form configures appearance before anything is persisted.
    private var flagIcon: String {
        let name = booleanOptions.flagIconName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return BooleanOptions.defaultFlagIconName }
        return name
    }

    private var flagColor: Color {
        Color(hex: booleanOptions.flagColorHex ?? BooleanOptions.defaultFlagColorHex)
    }

    /// Roles this field's type can actually carry. `.optionList` only reaches `.statusTabs`
    /// once it has enough options to make a tab bar meaningful.
    private var availableRoles: [DisplayRole] {
        DisplayRole.allCases.filter {
            FieldDefinitionValidation.supports(role: $0, fieldType: fieldType, optionCount: optionCount)
        }
    }

    private var showsSection: Bool {
        // A type with only the default role available has nothing to configure.
        availableRoles.count > 1 || displayRole != .none
    }

    private var needsMoreOptions: Bool {
        fieldType == .optionList && optionCount < FieldDefinitionValidation.minimumStatusOptions
    }

    private var truePlaceholder: String {
        fieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "Yes")
            : fieldName
    }

    var body: some View {
        if showsSection {
            Section {
                Picker("Show In Item List", selection: $displayRole) {
                    ForEach(availableRoles, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }

                if needsMoreOptions {
                    Text("Add at least \(FieldDefinitionValidation.minimumStatusOptions) options to use this field as a tab bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if displayRole == .statusTabs {
                    Toggle("Show \"All\" Tab", isOn: $showAllTab)
                }

                if displayRole == .statusTabs, let otherStatusFieldName {
                    // Only one tab bar per catalogue — say so plainly rather than silently
                    // demoting the other field on save.
                    Label(
                        "\"\(otherStatusFieldName)\" currently drives the tab bar. Saving will move it to this field.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Display")
            } footer: {
                Text(displayRole == .statusTabs
                     ? roleFooter + " " + String(localized: "The \"All\" tab shows every item regardless of status.")
                     : roleFooter)
            }

            // Several flags on one catalogue need to be told apart at a glance, so each
            // picks its own symbol and tint rather than all rendering as a yellow star.
            if displayRole == .flagFilter {
                Section {
                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack {
                            Text("Icon")
                            Spacer()
                            Image(systemName: flagIcon)
                                .font(.title3)
                                .foregroundStyle(flagColor)
                                .frame(width: 32, height: 32)
                                .background(flagColor.opacity(0.15))
                                .clipShape(.rect(cornerRadius: 6))
                        }
                    }
                    .foregroundStyle(.primary)
                    .sheet(isPresented: $showingIconPicker) {
                        IconPickerView(selectedIcon: Binding(
                            get: { flagIcon },
                            set: { booleanOptions.flagIconName = $0 }
                        ))
                    }

                    ColorPicker("Colour", selection: Binding(
                        get: { flagColor },
                        set: { booleanOptions.flagColorHex = $0.toHex() }
                    ), supportsOpacity: false)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Used for the filter toggle in the toolbar and the badge on each flagged item.")
                }
            }

            // Only a boolean tab bar has two tabs that need naming; every other combination
            // takes its labels from the option values or needs none at all.
            if displayRole == .statusTabs && fieldType == .boolean {
                Section {
                    TextField(truePlaceholder, text: Binding(
                        get: { booleanOptions.trueLabel ?? "" },
                        set: { booleanOptions.trueLabel = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Other", text: Binding(
                        get: { booleanOptions.falseLabel ?? "" },
                        set: { booleanOptions.falseLabel = $0.isEmpty ? nil : $0 }
                    ))
                    Picker("New Items Start As", selection: $booleanOptions.defaultValue) {
                        Text(booleanOptions.trueLabel ?? truePlaceholder).tag(true)
                        Text(booleanOptions.falseLabel ?? String(localized: "Other")).tag(false)
                    }
                } header: {
                    Text("Tab Labels")
                } footer: {
                    Text("Names the two tabs in the item list. Leave blank to use \"\(truePlaceholder)\" and \"Other\".")
                }
            }
        }
    }

    private var roleFooter: String {
        switch displayRole {
        case .none:
            return String(localized: "An ordinary field, edited on the item's detail form.")
        case .statusTabs:
            return fieldType == .boolean
                ? String(localized: "Adds a two-tab bar to the item list. Each item is in one tab or the other.")
                : String(localized: "Adds a tab bar to the item list — one tab per option, in the order you define them.")
        case .flagFilter:
            return String(localized: "Adds a filter toggle to the toolbar. Items can be flagged independently of everything else.")
        }
    }
}
