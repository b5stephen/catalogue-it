//
//  BooleanOptionsSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Boolean Options Section

/// Shown for every Yes/No field. The filter button's icon and colour are editable only while
/// the field is a flag filter; they stay on the draft either way, so a field promoted to a role
/// later arrives with its appearance already set.
struct BooleanOptionsSection: View {
    @Binding var draft: FieldDefinitionDraft

    @State private var showingIconPicker = false
    @ScaledMetric private var captionWidth: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    /// `FieldDefinition.statusTabLabels`' fallback, so the placeholder is what renders.
    private var truePlaceholder: String { String(localized: "Yes") }
    private var falsePlaceholder: String { String(localized: "No") }

    private var isStatusField: Bool { draft.displayRole == .statusTabs }
    private var isFilterOn: Bool { draft.displayRole == .flagFilter }

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var captionName: String { trimmedName.isEmpty ? String(localized: "these") : trimmedName }

    private var suggestions: FlagIconSuggestions.Result {
        FlagIconSuggestions.suggestions(for: trimmedName)
    }

    /// Darkened in light mode: system yellow on a pale tint is too faint for small text.
    private var nudgeTextColor: Color {
        colorScheme == .dark ? .yellow : Color.orange.mix(with: .black, by: 0.55)
    }

    var body: some View {
        valuesSection
        filterSection
    }

    // MARK: - Values

    private var valuesSection: some View {
        Section {
            labelRow(caption: "On", accessibility: "Label when on", placeholder: truePlaceholder, text: Binding(
                get: { draft.booleanOptions.trueLabel ?? "" },
                set: { draft.booleanOptions.trueLabel = $0.isEmpty ? nil : $0 }
            ))
            labelRow(caption: "Off", accessibility: "Label when off", placeholder: falsePlaceholder, text: Binding(
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
            Text("Values")
        } footer: {
            Text("Labels are optional, e.g. Built / Not Built.")
        }
    }

    private func labelRow(
        caption: LocalizedStringKey,
        accessibility: LocalizedStringKey,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            Text(caption)
                .foregroundStyle(.secondary)
                .frame(width: captionWidth, alignment: .leading)
            TextField(placeholder, text: text)
                .accessibilityLabel(accessibility)
        }
    }

    // MARK: - Filter Button

    private var filterSection: some View {
        Section {
            Toggle(isOn: filterBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show in Toolbar")
                    Text(toggleCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // One role per field: say why it's unavailable rather than silently take the tab bar's.
            .disabled(isStatusField)
            .accessibilityIdentifier("flag-filter-toggle")

            if isFilterOn {
                iconRow
                if draft.flagIconName == nil {
                    nudgePanel
                } else {
                    colorRow
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

    private var toggleCaption: LocalizedStringKey {
        isStatusField
            ? "Used for the Tab Bar"
            : "Adds a button to the item list that shows only \(captionName) items. Tap it again to show everything."
    }

    // MARK: - Icon

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

    // MARK: - Nudge

    /// Inner radius = outer − padding (see the card-design skill); the outer is roughly the
    /// Form row's inset from the section card's own corner.
    private enum Nudge {
        static let inset: CGFloat = 8
        static let padding: CGFloat = 12
        static let cornerRadius: CGFloat = AppConstants.CornerRadius.card
        static let buttonCornerRadius: CGFloat = cornerRadius - padding
    }

    private var nudgePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose an icon so the button is easy to spot. \(captionName) items also show it in the list. Without one, the button is a plain filter symbol.")
                .font(.footnote)

            Text(suggestionCaption)
                .font(.caption.weight(.semibold))

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
        .foregroundStyle(nudgeTextColor)
        .padding(Nudge.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.yellow.opacity(0.18),
            in: .rect(cornerRadius: Nudge.cornerRadius, style: .continuous)
        )
        .listRowInsets(EdgeInsets(top: Nudge.inset, leading: Nudge.inset, bottom: Nudge.inset, trailing: Nudge.inset))
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
                    .background,
                    in: .rect(cornerRadius: Nudge.buttonCornerRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
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

    return TabView {
        Form { BooleanOptionsSection(draft: $plain) }
            .tabItem { Text("Off") }
        Form { BooleanOptionsSection(draft: $nudged) }
            .tabItem { Text("No Icon") }
        Form { BooleanOptionsSection(draft: $configured) }
            .tabItem { Text("Configured") }
        Form { BooleanOptionsSection(draft: $tabBar) }
            .tabItem { Text("Tab Bar") }
    }
}
