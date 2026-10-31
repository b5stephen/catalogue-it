//
//  TabBarSettingsView.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Tab Bar Settings

/// A projection of `FieldDefinitionDraft.displayRole` across the field set, so nothing new is
/// persisted. A single `Picker` can't choose two status fields, which makes one tab bar per
/// catalogue structural.
struct TabBarSettingsView: View {
    @Binding var fields: [FieldDefinitionDraft]
    @Binding var showAllTab: Bool
    let colorHex: String

    private var statusCandidates: [FieldDefinitionDraft] {
        FieldDefinitionValidation.statusEligibleDrafts(in: fields)
    }

    /// Named so their absence from the picker isn't a mystery.
    private var underfilledOptionLists: [FieldDefinitionDraft] {
        fields.filter { $0.fieldType == .optionList && !FieldDefinitionValidation.supportsStatusTabs($0) }
    }

    private var selectedStatusID: Binding<UUID?> {
        Binding(
            get: { FieldDefinitionValidation.statusFieldID(in: fields) },
            set: { fields = FieldDefinitionValidation.settingStatusField(to: $0, in: fields) }
        )
    }

    private var previewTabs: [StatusTabDescriptor] {
        guard let id = selectedStatusID.wrappedValue,
              let field = fields.first(where: { $0.id == id })
        else { return [] }
        return StatusTabDescriptor.tabs(
            fieldType: field.fieldType,
            options: field.optionListOptions.options,
            booleanLabels: field.booleanOptions.resolvedLabels,
            showAllTab: showAllTab
        )
    }

    var body: some View {
        Form {
            Section {
                preview
            }

            Section {
                Picker("Field", selection: selectedStatusID) {
                    Text("None").tag(UUID?.none)
                    ForEach(statusCandidates) { field in
                        Text(field.displayName).tag(UUID?.some(field.id))
                    }
                }
                .disabled(statusCandidates.isEmpty)

                if selectedStatusID.wrappedValue != nil {
                    Toggle("Show \"All\" Tab", isOn: $showAllTab)
                }
            } footer: {
                Text(footer)
            }

            if !underfilledOptionLists.isEmpty {
                Section {
                    ForEach(underfilledOptionLists) { field in
                        LabeledContent(field.displayName) {
                            Text("Needs \(FieldDefinitionValidation.minimumStatusOptions)+ options")
                        }
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Not Available")
                } footer: {
                    Text("Option List fields need at least \(FieldDefinitionValidation.minimumStatusOptions) options before they can drive tabs.")
                }
            }
        }
        .navigationTitle("Tab Bar")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var footer: String {
        guard !statusCandidates.isEmpty else {
            return String(localized: "Add a Yes/No or Option List field to give the item list a tab bar.")
        }
        var text = String(localized: "One tab per option, or two for a Yes/No field.")
        if selectedStatusID.wrappedValue != nil {
            text += " " + String(localized: "The \"All\" tab shows every item regardless of status.")
        }
        return text
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        let tabs = previewTabs
        VStack(alignment: .leading, spacing: 14) {
            if tabs.isEmpty {
                Label("No tab bar", systemImage: "rectangle.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
            } else {
                // The real bar, bound to a fixed selection and shielded from touches, so the
                // preview can't drift from the item list.
                StatusTabBar(tabs: tabs, colorHex: colorHex, selection: .constant(tabs[0].tab))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Tab bar preview")
                    .accessibilityValue(tabs.map(\.label).formatted(.list(type: .and)))
            }
            ItemListSkeleton()
        }
        .padding(.vertical, 4)
        .animation(.default, value: tabs.map(\.label))
    }
}

// MARK: - Preview

#Preview("Tab Bar") {
    @Previewable @State var fields: [FieldDefinitionDraft] = {
        var status = FieldDefinitionDraft(name: "Status", fieldType: .optionList, priority: 0)
        status.optionListOptions = OptionListOptions(options: ["Owned", "Wishlist", "On Order"])
        status.displayRole = .statusTabs
        let built = FieldDefinitionDraft(name: "Built", fieldType: .boolean, priority: 1)
        var scale = FieldDefinitionDraft(name: "Scale", fieldType: .optionList, priority: 2)
        scale.optionListOptions = OptionListOptions(options: ["1:48"])
        return [status, built, scale]
    }()
    @Previewable @State var showAllTab = true

    NavigationStack {
        TabBarSettingsView(fields: $fields, showAllTab: $showAllTab, colorHex: "#E8590C")
    }
}

#Preview("Tab Bar — Nothing Eligible") {
    @Previewable @State var fields: [FieldDefinitionDraft] = [
        FieldDefinitionDraft(name: "Name", fieldType: .text, priority: 0),
        FieldDefinitionDraft(name: "Year", fieldType: .number, priority: 1),
    ]
    @Previewable @State var showAllTab = false

    NavigationStack {
        TabBarSettingsView(fields: $fields, showAllTab: $showAllTab, colorHex: "#E8590C")
    }
}
