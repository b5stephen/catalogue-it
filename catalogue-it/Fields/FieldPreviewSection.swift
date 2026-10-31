//
//  FieldPreviewSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Preview Section

/// Renders through the real screens' views (`FieldControl`, `FieldValueFormatter`,
/// `FieldChipView`), so it can't drift from what the field becomes.
struct FieldPreviewSection: View {
    let name: String
    let fieldType: FieldType
    var numberOptions: NumberOptions = NumberOptions()
    var optionListOptions: OptionListOptions = OptionListOptions()
    var booleanOptions: BooleanOptions = BooleanOptions()
    var displayRole: DisplayRole = .none

    @State private var textValue: String = ""
    @State private var numberValue: Double? = nil
    @State private var dateValue: Date? = nil
    @State private var boolValue: Bool = false

    /// The name row's placeholder, for a field not yet named.
    private var label: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Field Name") : trimmed
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("When adding an item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FieldControl(
                    label: label,
                    fieldType: fieldType,
                    numberOptions: numberOptions,
                    optionListOptions: optionListOptions,
                    textValue: $textValue,
                    numberValue: $numberValue,
                    dateValue: $dateValue,
                    boolValue: $boolValue
                )
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("On the item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    displayedValue
                }
            }
            .padding(.vertical, 2)

            if showsToolbarButton {
                toolbarPreview
            }
        } header: {
            Text("Preview")
        } footer: {
            Text("Try it out — the sample value above updates as you change the field's settings.")
        }
        .onAppear { seedSample() }
        .onChange(of: fieldType) { seedSample() }
        .onChange(of: optionListOptions) { seedOptionListSampleIfNeeded() }
        .onChange(of: booleanOptions.defaultValue) { boolValue = booleanOptions.defaultValue }
    }

    // MARK: - Toolbar Button

    private var showsToolbarButton: Bool {
        fieldType == .boolean && displayRole == .flagFilter
    }

    /// A lone flag is a toolbar button of its own, labelled with the field's icon.
    private var toolbarPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In the item list")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: trimmedLabel(booleanOptions.flagIconName) ?? BooleanOptions.fallbackFilterIconName)
                .font(.body)
                .frame(width: 44, height: 36)
                .background(.fill.tertiary, in: .capsule)
                .accessibilityLabel(label)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Display Line

    @ViewBuilder
    private var displayedValue: some View {
        switch fieldType {
        case .text:
            plainText(textValue)
        case .number:
            plainText(numberValue.map { FieldValueFormatter.number($0, options: numberOptions) } ?? "")
        case .date:
            plainText(dateValue.map { FieldValueFormatter.date($0) } ?? "")
        case .boolean:
            booleanDisplay
        case .optionList:
            optionListDisplay
        }
    }

    @ViewBuilder
    private var booleanDisplay: some View {
        let labels = (
            trueLabel: trimmedLabel(booleanOptions.trueLabel) ?? String(localized: "Yes"),
            falseLabel: trimmedLabel(booleanOptions.falseLabel) ?? String(localized: "No")
        )
        switch displayRole {
        case .statusTabs:
            FieldChipView(
                text: boolValue ? labels.trueLabel : labels.falseLabel,
                tint: StatusChipPalette.booleanTint(isTrue: boolValue)
            )
        case .flagFilter:
            if boolValue, let icon = trimmedLabel(booleanOptions.flagIconName) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(flagColor ?? .accentColor)
                    .accessibilityLabel(label)
            } else {
                emptyPlaceholder
            }
        case .none:
            plainText(FieldValueFormatter.boolean(boolValue))
        }
    }

    @ViewBuilder
    private var optionListDisplay: some View {
        if textValue.isEmpty {
            emptyPlaceholder
        } else if displayRole == .statusTabs {
            FieldChipView(
                text: textValue,
                tint: StatusChipPalette.tint(optionIndex: optionListOptions.options.firstIndex(of: textValue))
            )
        } else {
            Text(textValue)
        }
    }

    @ViewBuilder
    private func plainText(_ value: String) -> some View {
        if value.isEmpty {
            emptyPlaceholder
        } else {
            Text(value)
        }
    }

    private var emptyPlaceholder: some View {
        Text(verbatim: "—")
            .foregroundStyle(.tertiary)
    }

    private var flagColor: Color? {
        trimmedLabel(booleanOptions.flagColorHex).flatMap { Color(hex: $0) }
    }

    private func trimmedLabel(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Sample Value

    private func seedSample() {
        textValue = ""
        numberValue = nil
        dateValue = nil
        boolValue = booleanOptions.defaultValue

        switch fieldType {
        case .text:
            textValue = String(localized: "Sample text")
        case .number:
            numberValue = 1234.5
        case .date:
            dateValue = .now
        case .boolean:
            break
        case .optionList:
            seedOptionListSampleIfNeeded()
        }
    }

    /// Options can be renamed or deleted while the preview is on screen.
    private func seedOptionListSampleIfNeeded() {
        guard fieldType == .optionList else { return }
        guard !optionListOptions.options.contains(textValue) else { return }
        textValue = optionListOptions.defaultValue ?? optionListOptions.options.sorted().first ?? ""
    }
}

// MARK: - Preview

#Preview("Field Previews") {
    Form {
        FieldPreviewSection(name: "Manufacturer", fieldType: .text)
        FieldPreviewSection(
            name: "Purchase Price",
            fieldType: .number,
            numberOptions: NumberOptions(format: .currency, precision: 2)
        )
        FieldPreviewSection(name: "Acquired", fieldType: .date)
        FieldPreviewSection(
            name: "Condition",
            fieldType: .optionList,
            optionListOptions: OptionListOptions(options: ["Mint", "Good", "Damaged"], defaultValue: "Good"),
            displayRole: .statusTabs
        )
        FieldPreviewSection(
            name: "Wishlist",
            fieldType: .boolean,
            booleanOptions: BooleanOptions(defaultValue: true, flagIconName: "star.fill", flagColorHex: "#FFCC00"),
            displayRole: .flagFilter
        )
    }
}
