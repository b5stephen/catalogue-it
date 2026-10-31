//
//  ItemListSettingsSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Item List Settings Section

/// Summary rows that push to a page each. The pages edit the form's own state through bindings,
/// so Save, Cancel and the unsaved-changes guard see their edits like any other.
struct ItemListSettingsSection: View {
    @Binding var fields: [FieldDefinitionDraft]
    @Binding var showAllTab: Bool
    @Binding var layoutOptions: CatalogueLayoutOptions
    /// For the tab bar preview's tint.
    let colorHex: String

    private var tabBarSummary: String {
        guard let id = FieldDefinitionValidation.statusFieldID(in: fields),
              let field = fields.first(where: { $0.id == id })
        else { return String(localized: "None") }
        return field.displayName
    }

    private var filtersSummary: String {
        let filters = fields.filter { FieldDefinitionValidation.resolvedRole(for: $0) == .flagFilter }
        switch filters.count {
        case 0: return String(localized: "None")
        case 1: return filters[0].displayName
        default: return String(localized: "\(filters.count) filters")
        }
    }

    var body: some View {
        Section {
            NavigationLink {
                TabBarSettingsView(fields: $fields, showAllTab: $showAllTab, colorHex: colorHex)
            } label: {
                SettingsSummaryLabel(
                    title: "Tab Bar",
                    value: tabBarSummary,
                    systemImage: "rectangle.split.3x1.fill",
                    tint: .blue
                )
            }

            NavigationLink {
                FilterTogglesSettingsView(fields: $fields)
            } label: {
                SettingsSummaryLabel(
                    title: "Filter Toggles",
                    value: filtersSummary,
                    systemImage: "line.3.horizontal.decrease",
                    tint: .orange
                )
            }

            NavigationLink {
                ItemLayoutSettingsView(layoutOptions: $layoutOptions)
            } label: {
                SettingsSummaryLabel(
                    title: "Item Layout",
                    value: layoutOptions.detailLabelLayout.title,
                    systemImage: "list.bullet.rectangle.fill",
                    tint: .gray
                )
            }
        } header: {
            Text("Item List")
        } footer: {
            Text("Optional. How the item list is split into tabs, filtered and laid out.")
        }
    }
}

// MARK: - Summary Label

private struct SettingsSummaryLabel: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        LabeledContent {
            Text(value)
                .lineLimit(1)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: .rect(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
            }
        }
    }
}

// MARK: - Item List Skeleton

/// Stand-in rows under a settings page's preview, to give the preview something to sit above.
struct ItemListSkeleton: View {
    var rowCount = 2

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rowCount, id: \.self) { index in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(.quaternary).frame(width: index.isMultiple(of: 2) ? 110 : 140, height: 8)
                        Capsule().fill(.quaternary).frame(width: 60, height: 6)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
