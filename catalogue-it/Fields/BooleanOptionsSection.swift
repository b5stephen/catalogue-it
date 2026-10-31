//
//  BooleanOptionsSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Boolean Options Section

/// Shown for every Yes/No field. The icon is the field's own, used wherever it shows, so it is
/// editable whatever the role; a status field hides it, since the tab bar's chips stand in.
struct BooleanOptionsSection: View {
    @Binding var draft: FieldDefinitionDraft

    @State private var showingIconPicker = false
    @ScaledMetric private var captionWidth: CGFloat = 44
    @ScaledMetric private var captionIconSize: CGFloat = 15

    private var isStatusField: Bool { draft.displayRole == .statusTabs }
    private var isFilterOn: Bool { draft.displayRole == .flagFilter }

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var captionName: String { trimmedName.isEmpty ? String(localized: "these") : trimmedName }

    private var suggestions: FlagIconSuggestions.Result {
        FlagIconSuggestions.suggestions(for: trimmedName)
    }

    var body: some View {
        if !isStatusField {
            iconSection
        }
        labelsSection
        filterSection
    }

    // MARK: - Icon

    private var iconSection: some View {
        Section {
            iconRow
            if draft.flagIconName == nil {
                suggestionsRow
            } else {
                colorRow
            }
        } header: {
            Text("Icon")
        } footer: {
            Text(iconFooter)
        }
    }

    private var iconFooter: LocalizedStringKey {
        draft.flagIconName == nil
            ? "Optional. Choose one to mark \(captionName) items with a badge in the item list, and to tap an icon instead of a switch when editing."
            : "Shows on \(captionName) items: as a badge in the item list, next to the value on the item page, and as a button to tap when editing."
    }

    private var iconRow: some View {
        Button {
            showingIconPicker = true
        } label: {
            HStack(spacing: 8) {
                Text("Icon")
                Spacer()
                FlagIconTile(icon: draft.flagIconName, color: draft.flagColor, size: 32)
                if draft.flagIconName == nil {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Icon")
        .accessibilityValue(draft.flagIconName ?? String(localized: "None"))
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(optionalIcon: Binding(
                get: { draft.flagIconName },
                set: { draft.booleanOptions.flagIconName = $0 }
            ))
        }
    }

    // MARK: - Suggestions

    private var suggestionsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestionCaption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(suggestions.symbols, id: \.self) { symbol in
                    suggestionButton {
                        draft.booleanOptions.flagIconName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(symbol)
                }
                suggestionButton {
                    showingIconPicker = true
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("More Icons")
            }
        }
        .padding(.vertical, 4)
    }

    private var suggestionCaption: String {
        suggestions.matched
            ? String(localized: "Suggested for “\(trimmedName)”")
            : String(localized: "Suggestions")
    }

    private func suggestionButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .font(.body)
                .foregroundStyle(.primary)
                // Flexes below 44pt only when seven won't fit across a phone-width row.
                .frame(maxWidth: 44, minHeight: 40, maxHeight: 40)
                .background(
                    .fill.tertiary,
                    in: .rect(cornerRadius: AppConstants.CornerRadius.small, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Labels

    private var labelsSection: some View {
        Section {
            labelRow(isOn: true, caption: "On", accessibility: "Label when on", text: Binding(
                get: { draft.booleanOptions.trueLabel ?? "" },
                set: { draft.booleanOptions.trueLabel = $0.isEmpty ? nil : $0 }
            ))
            labelRow(isOn: false, caption: "Off", accessibility: "Label when off", text: Binding(
                get: { draft.booleanOptions.falseLabel ?? "" },
                set: { draft.booleanOptions.falseLabel = $0.isEmpty ? nil : $0 }
            ))

            LabeledContent("New Items") {
                let labels = draft.booleanOptions.resolvedLabels
                Picker("New Items", selection: $draft.booleanOptions.defaultValue) {
                    Text(labels.trueLabel).tag(true)
                    Text(labels.falseLabel).tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
            }
        } header: {
            Text("Labels")
        } footer: {
            Text(labelsFooter)
        }
    }

    private var labelsFooter: LocalizedStringKey {
        let labels = draft.booleanOptions.resolvedLabels
        if isStatusField {
            return "Name the tabs and the value on the item page, e.g. Built / Not Built."
        }
        if draft.showsIconBadge {
            return "Shown on the item page and when editing. In the item list, the icon stands in for “\(labels.trueLabel)” and “\(labels.falseLabel)” shows nothing."
        }
        return "Shown instead of Yes and No, e.g. Built / Not Built."
    }

    /// The placeholder is `BooleanOptions.resolvedLabels`' fallback, so it is what renders.
    private func labelRow(
        isOn: Bool,
        caption: LocalizedStringKey,
        accessibility: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                if draft.showsIconBadge, let icon = draft.flagIconName {
                    BooleanIconImage(icon: icon, color: draft.flagColor, isOn: isOn)
                        .font(.system(size: captionIconSize))
                }
                Text(caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: captionWidth, alignment: .leading)
            TextField(BooleanOptions().label(for: isOn), text: text)
                .accessibilityLabel(accessibility)
        }
    }

    // MARK: - Filter Button

    private var filterSection: some View {
        Section {
            Toggle(isOn: filterBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show in Toolbar")
                    toggleCaption
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // One role per field: say why it's unavailable rather than silently take the tab bar's.
            .disabled(isStatusField)
            .accessibilityIdentifier("flag-filter-toggle")

            if isFilterOn, draft.flagIconName == nil {
                Label {
                    Text("The button uses this filter symbol until you choose an icon above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: BooleanOptions.fallbackFilterIconName)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Filter Button")
        } footer: {
            Text("Filter buttons combine, so people can show items that match any mix.")
        }
    }

    private var filterBinding: Binding<Bool> {
        Binding(
            get: { isFilterOn },
            set: { draft = FieldDefinitionValidation.settingFlagFilter($0, for: draft.id, in: [draft])[0] }
        )
    }

    /// The chosen icon inline, so it's clear the button is labelled with it.
    private var toggleCaption: Text {
        if isStatusField {
            return Text("Used for the Tab Bar")
        }
        if let icon = draft.flagIconName {
            let symbol = Text(Image(systemName: icon)).foregroundStyle(draft.flagColor ?? .accentColor)
            return Text("Adds a \(symbol) button to the item list that shows only \(captionName) items. Tap it again to show everything.")
        }
        return Text("Adds a button to the item list that shows only \(captionName) items. Tap it again to show everything.")
    }

    // MARK: - Colour

    private static let presetColors: [(name: LocalizedStringKey, hex: String)] = [
        ("Green", "#2B7A3B"),
        ("Yellow", "#C08A00"),
        ("Orange", "#C2410C"),
        ("Red", "#C92A2A"),
        ("Blue", "#1864AB"),
        ("Purple", "#5F3DC4")
    ]

    private var selectedHex: String? {
        let hex = draft.booleanOptions.flagColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hex, !hex.isEmpty else { return nil }
        return hex.uppercased()
    }

    private var isCustomColor: Bool {
        guard let selectedHex else { return false }
        return !Self.presetColors.contains { $0.hex == selectedHex }
    }

    private var colorRow: some View {
        HStack(spacing: 4) {
            ForEach(Self.presetColors, id: \.hex) { preset in
                Button {
                    draft.booleanOptions.flagColorHex = preset.hex
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: 24, height: 24)
                        .padding(3)
                        .modifier(SelectionRing(isSelected: selectedHex == preset.hex))
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(preset.name))
                .accessibilityAddTraits(selectedHex == preset.hex ? .isSelected : [])
            }

            ColorPicker("Custom Colour", selection: Binding(
                get: { draft.flagColor ?? .accentColor },
                set: { draft.booleanOptions.flagColorHex = $0.toHex() }
            ), supportsOpacity: false)
            .labelsHidden()
            .padding(3)
            .modifier(SelectionRing(isSelected: isCustomColor))

            Spacer(minLength: 8)

            Button("Remove") {
                draft.booleanOptions.flagIconName = nil
                draft.booleanOptions.flagColorHex = nil
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Selection Ring

private struct SelectionRing: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isSelected {
                Circle().strokeBorder(.secondary, lineWidth: 2)
            }
        }
    }
}

// MARK: - Preview

#Preview("Yes/No Options") {
    @Previewable @State var configured: FieldDefinitionDraft = {
        var draft = FieldDefinitionDraft(name: "Built", fieldType: .boolean, priority: 0)
        draft.displayRole = .flagFilter
        draft.booleanOptions = BooleanOptions(
            trueLabel: "Built",
            falseLabel: "Not Built",
            defaultValue: false,
            flagIconName: "hammer.fill",
            flagColorHex: "#2B7A3B"
        )
        return draft
    }()
    @Previewable @State var nudged: FieldDefinitionDraft = {
        var draft = FieldDefinitionDraft(name: "Favourite", fieldType: .boolean, priority: 0)
        draft.displayRole = .flagFilter
        return draft
    }()
    @Previewable @State var tabBar: FieldDefinitionDraft = {
        var draft = FieldDefinitionDraft(name: "Owned", fieldType: .boolean, priority: 0)
        draft.displayRole = .statusTabs
        return draft
    }()
    @Previewable @State var plain = FieldDefinitionDraft(name: "Wishlist", fieldType: .boolean, priority: 0)
    @Previewable @State var iconOnly: FieldDefinitionDraft = {
        var draft = FieldDefinitionDraft(name: "Has Box", fieldType: .boolean, priority: 0)
        draft.booleanOptions = BooleanOptions(flagIconName: "shippingbox.fill", flagColorHex: "#1864AB")
        return draft
    }()

    return TabView {
        Form { BooleanOptionsSection(draft: $plain) }
            .tabItem { Text("Plain") }
        Form { BooleanOptionsSection(draft: $iconOnly) }
            .tabItem { Text("Icon") }
        Form { BooleanOptionsSection(draft: $nudged) }
            .tabItem { Text("Filter, No Icon") }
        Form { BooleanOptionsSection(draft: $configured) }
            .tabItem { Text("Configured") }
        Form { BooleanOptionsSection(draft: $tabBar) }
            .tabItem { Text("Tab Bar") }
    }
}
