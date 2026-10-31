//
//  FilterTogglesSettingsView.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Filter Toggles Settings

struct FilterTogglesSettingsView: View {
    @Binding var fields: [FieldDefinitionDraft]

    private var flagCandidates: [FieldDefinitionDraft] {
        FieldDefinitionValidation.flagEligibleDrafts(in: fields)
    }

    private var enabledFilters: [FieldDefinitionDraft] {
        flagCandidates.filter { FieldDefinitionValidation.resolvedRole(for: $0) == .flagFilter }
    }

    var body: some View {
        Form {
            Section {
                preview
            }

            Section {
                if flagCandidates.isEmpty {
                    Text("No Yes/No fields yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(flagCandidates) { field in
                        FilterToggleRow(
                            field: field,
                            isOn: Binding(
                                get: { field.displayRole == .flagFilter },
                                set: { fields = FieldDefinitionValidation.settingFlagFilter($0, for: field.id, in: fields) }
                            )
                        )
                    }
                }
            } header: {
                Text("Yes/No Fields")
            } footer: {
                Text(flagCandidates.isEmpty
                     ? String(localized: "Add a Yes/No field to give the item list a filter toggle.")
                     : String(localized: "Each toggle adds a button to the item list's toolbar. Filters combine, so items can match any mix."))
            }
        }
        .navigationTitle("Filter Toggles")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    // MARK: - Preview

    /// Mirrors `FlagFilterButton`: one filter is a button of its own, several collapse into a
    /// single menu.
    private var previewSymbol: String? {
        let filters = enabledFilters
        switch filters.count {
        case 0: return nil
        case 1: return filters[0].flagIconName ?? BooleanOptions.fallbackFilterIconName
        default: return BooleanOptions.fallbackFilterIconName
        }
    }

    private var previewCaption: String {
        let count = enabledFilters.count
        switch count {
        case 0: return String(localized: "No filter buttons in the toolbar")
        case 1: return String(localized: "1 filter button in the toolbar")
        default: return String(localized: "\(count) filters, grouped in one toolbar menu")
        }
    }

    private var preview: some View {
        HStack(spacing: 12) {
            Image(systemName: previewSymbol ?? "slash.circle")
                .font(.body)
                .foregroundStyle(previewSymbol == nil ? .tertiary : .primary)
                .frame(width: 44, height: 36)
                .background(.fill.tertiary, in: .capsule)
                .accessibilityHidden(true)
            Text(previewCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .animation(.default, value: previewSymbol)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewCaption)
    }
}

// MARK: - Filter Toggle Row

private struct FilterToggleRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let field: FieldDefinitionDraft
    @Binding var isOn: Bool

    private static let tileSize: CGFloat = 30

    private var isStatus: Bool { field.displayRole == .statusTabs }

    /// Darkened in light mode: system orange on white is too faint for small text.
    private var warningStyle: Color {
        colorScheme == .dark ? .orange : Color.orange.mix(with: .black, by: 0.4)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                tile
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.displayName)
                    caption
                }
            }
        }
        // One role per field: say why it's unavailable rather than leave a dead switch.
        .disabled(isStatus)
    }

    private var tile: some View {
        FlagIconTile(icon: field.flagIconName, color: field.flagColor, size: Self.tileSize)
    }

    @ViewBuilder
    private var caption: some View {
        if isStatus {
            Text("Used for the Tab Bar")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if field.flagIconName == nil {
            Text("No icon yet. Set one in the field.")
                .font(.caption)
                .foregroundStyle(warningStyle)
        }
    }
}

// MARK: - Preview

#Preview("Filter Toggles") {
    @Previewable @State var fields: [FieldDefinitionDraft] = {
        var status = FieldDefinitionDraft(name: "Owned", fieldType: .boolean, priority: 0)
        status.displayRole = .statusTabs
        var favourite = FieldDefinitionDraft(name: "Favourite", fieldType: .boolean, priority: 1)
        favourite.displayRole = .flagFilter
        favourite.booleanOptions.flagIconName = "star.fill"
        favourite.booleanOptions.flagColorHex = "#F5B700"
        let built = FieldDefinitionDraft(name: "Built", fieldType: .boolean, priority: 2)
        return [status, favourite, built]
    }()

    NavigationStack {
        FilterTogglesSettingsView(fields: $fields)
    }
}

#Preview("Filter Toggles — No Yes/No Fields") {
    @Previewable @State var fields: [FieldDefinitionDraft] = [
        FieldDefinitionDraft(name: "Name", fieldType: .text, priority: 0),
    ]

    NavigationStack {
        FilterTogglesSettingsView(fields: $fields)
    }
}
