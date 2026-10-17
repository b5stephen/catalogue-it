//
//  CatalogueOptionsSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Catalogue Options Section

/// A projection of `FieldDefinitionDraft.displayRole` across the field set, so nothing new is
/// persisted. A single `Picker` can't choose two status fields, which makes one tab bar per
/// catalogue structural.
struct CatalogueOptionsSection: View {
    @Binding var fields: [FieldDefinitionDraft]
    @Binding var showAllTab: Bool

    private var statusCandidates: [FieldDefinitionDraft] {
        FieldDefinitionValidation.statusEligibleDrafts(in: fields)
    }

    private var flagCandidates: [FieldDefinitionDraft] {
        FieldDefinitionValidation.flagEligibleDrafts(in: fields)
    }

    /// Option-list fields short of enough options, named in the footer so their absence isn't a
    /// mystery.
    private var underfilledOptionListNames: [String] {
        fields
            .filter { $0.fieldType == .optionList && !FieldDefinitionValidation.supportsStatusTabs($0) }
            .map { displayName(for: $0) }
    }

    private var selectedStatusID: Binding<UUID?> {
        Binding(
            get: { FieldDefinitionValidation.statusFieldID(in: fields) },
            set: { fields = FieldDefinitionValidation.settingStatusField(to: $0, in: fields) }
        )
    }

    var body: some View {
        // Always shown, even with no eligible field: otherwise there's no way to learn that a Yes/No
        // field is what creates a filter toggle.
        Section {
            Picker("Field", selection: selectedStatusID) {
                Text("None").tag(UUID?.none)
                ForEach(statusCandidates) { field in
                    Text(displayName(for: field)).tag(UUID?.some(field.id))
                }
            }
            .disabled(statusCandidates.isEmpty)

            if selectedStatusID.wrappedValue != nil {
                Toggle("Show \"All\" Tab", isOn: $showAllTab)
            }
        } header: {
            Text("Tab Bar")
        } footer: {
            Text(statusFooter)
        }

        Section {
            if flagCandidates.isEmpty {
                Text("No Yes/No fields yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(flagCandidates) { field in
                    let isStatus = field.displayRole == .statusTabs
                    Toggle(isOn: Binding(
                        get: { field.displayRole == .flagFilter },
                        set: { fields = FieldDefinitionValidation.settingFlagFilter($0, for: field.id, in: fields) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName(for: field))
                            // One role per field: say why it's unavailable rather than leave a dead switch.
                            if isStatus {
                                Text("Used for the Tab Bar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isStatus)
                }
            }
        } header: {
            Text("Filter Toggles")
        } footer: {
            Text(flagCandidates.isEmpty
                 ? String(localized: "Add a Yes/No field to give the item list a filter toggle.")
                 : String(localized: "Each toggle adds an independent filter to the toolbar. Items can be flagged in any combination."))
        }
    }

    private var statusFooter: String {
        var text = statusCandidates.isEmpty
            ? String(localized: "Add a Yes/No or Option List field to give the item list a tab bar.")
            : String(localized: "Adds a tab bar to the item list — one tab per option, or two tabs for a Yes/No field.")

        if selectedStatusID.wrappedValue != nil {
            text += " " + String(localized: "The \"All\" tab shows every item regardless of status.")
        }
        if !underfilledOptionListNames.isEmpty {
            let names = underfilledOptionListNames.map { "\"\($0)\"" }.joined(separator: ", ")
            text += " " + String(localized: "Needs at least \(FieldDefinitionValidation.minimumStatusOptions) options before it can drive tabs: \(names).")
        }
        return text
    }

    /// So an unnamed field is still selectable, not a blank row.
    private func displayName(for field: FieldDefinitionDraft) -> String {
        let trimmed = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Field") : trimmed
    }
}

// MARK: - Preview

#Preview("Options") {
    @Previewable @State var fields: [FieldDefinitionDraft] = {
        var status = FieldDefinitionDraft(name: "Status", fieldType: .optionList, priority: 0)
        status.optionListOptions = OptionListOptions(options: ["Owned", "Wishlist"])
        status.displayRole = .statusTabs
        var favourite = FieldDefinitionDraft(name: "Favourite", fieldType: .boolean, priority: 1)
        favourite.displayRole = .flagFilter
        let forSale = FieldDefinitionDraft(name: "For Sale", fieldType: .boolean, priority: 2)
        var condition = FieldDefinitionDraft(name: "Condition", fieldType: .optionList, priority: 3)
        condition.optionListOptions = OptionListOptions(options: ["Mint"])
        return [status, favourite, forSale, condition]
    }()
    @Previewable @State var showAllTab = true

    return Form {
        CatalogueOptionsSection(fields: $fields, showAllTab: $showAllTab)
    }
}

#Preview("Options — Nothing Eligible") {
    @Previewable @State var fields: [FieldDefinitionDraft] = [
        FieldDefinitionDraft(name: "Name", fieldType: .text, priority: 0),
        FieldDefinitionDraft(name: "Year", fieldType: .number, priority: 1),
    ]
    @Previewable @State var showAllTab = false

    return Form {
        CatalogueOptionsSection(fields: $fields, showAllTab: $showAllTab)
    }
}
