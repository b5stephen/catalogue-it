//
//  FieldPreviewSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Preview Context

/// The catalogue around the field being edited. Drafts, so unsaved reorders and renames show.
struct FieldPreviewContext {
    var fieldsBefore: [FieldDefinitionDraft] = []
    var fieldsAfter: [FieldDefinitionDraft] = []
    var layoutOptions = CatalogueLayoutOptions()
    var tint: Color = .accentColor
}

// MARK: - Field Preview Section

/// Mock screens with the field among the catalogue's own, whose values are placeholders.
/// Values go through the real `FieldControl`, `FieldValueFormatter` and `FieldChipView`;
/// placement mirrors `ItemDetailView` (title is the first field) and `ItemRowView` (title and two
/// summary lines from the `isSummaryField`s; status chip and icon badges trailing) — keep it, and
/// `CataloguePreviewView`, in step.
struct FieldPreviewSection: View {
    let name: String
    let fieldType: FieldType
    var numberOptions: NumberOptions = NumberOptions()
    var optionListOptions: OptionListOptions = OptionListOptions()
    var booleanOptions: BooleanOptions = BooleanOptions()
    var displayRole: DisplayRole = .none
    var context = FieldPreviewContext()

    @State private var screen: PreviewScreen = .itemPage
    @State private var textValue: String = ""
    @State private var numberValue: Double? = nil
    @State private var dateValue: Date? = nil
    @State private var boolValue: Bool = false

    private static let summaryLineCount = 2

    enum PreviewScreen: CaseIterable, Identifiable {
        case adding, itemList, itemPage
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .adding: "Form View"
            case .itemList: "List View"
            case .itemPage: "Card View"
            }
        }
    }

    /// The name row's placeholder, for a field not yet named.
    private var label: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Field Name") : trimmed
    }

    /// Set when the field shows its icon, as for `FieldDefinitionDraft.showsIconBadge`.
    private var badgeIcon: String? {
        guard fieldType == .boolean, displayRole != .statusTabs else { return nil }
        return trimmedLabel(booleanOptions.flagIconName)
    }

    private var isSummaryField: Bool {
        displayRole == .none && badgeIcon == nil
    }

    var body: some View {
        Section {
            VStack(spacing: 12) {
                Picker("Preview", selection: $screen) {
                    ForEach(PreviewScreen.allCases) { screen in
                        Text(screen.title).tag(screen)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                screenView
            }
            // Off the form's own row chrome, so the mock reads as a screen rather than a setting.
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Preview")
        } footer: {
            Text(footerText)
        }
        .onAppear { seedSample() }
        .onChange(of: fieldType) { seedSample() }
        .onChange(of: optionListOptions) { seedOptionListSampleIfNeeded() }
        .onChange(of: booleanOptions.defaultValue) { boolValue = booleanOptions.defaultValue }
    }

    private var footerText: LocalizedStringKey {
        switch screen {
        case .adding:
            "How the field displays when adding or editing its value. Try it out — a change here will be reflected in the other previews."
        case .itemPage:
            "How the field displays on an item's detail view card."
        case .itemList:
            "How the field displays on an item's list view card."
        }
    }

    private var screenView: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch screen {
            case .adding: addingScreen
            case .itemPage: itemPageScreen
            case .itemList: itemListScreen
            }
        }
        .mockScreen(tint: context.tint)
    }

    /// The real cards' fill, which in dark is a deep shade of the catalogue's colour.
    private var cardFill: CardFill {
        CardFill(colorHex: context.tint.toHex())
    }

    // MARK: - Adding

    /// The edit sheet shows an empty field as its name in placeholder grey.
    private var addingScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let before = context.fieldsBefore.last {
                neighbourInput(before)
                Divider()
            }
            FieldControl(
                label: label,
                fieldType: fieldType,
                numberOptions: numberOptions,
                optionListOptions: optionListOptions,
                booleanOptions: booleanOptions,
                booleanIcon: badgeIcon,
                booleanIconColor: flagColor,
                textValue: $textValue,
                numberValue: $numberValue,
                dateValue: $dateValue,
                boolValue: $boolValue
            )
            .padding(.vertical, 10)
            .highlighted()
            if let after = context.fieldsAfter.first {
                Divider()
                neighbourInput(after)
            }
        }
        .mockCard(fill: cardFill)
    }

    private func neighbourInput(_ field: FieldDefinitionDraft) -> some View {
        Text(field.displayName)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .accessibilityHidden(true)
    }

    // MARK: - Item Page

    private var itemPageScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if context.fieldsBefore.isEmpty {
                    Text(titleText.isEmpty ? String(localized: "Untitled Item") : titleText)
                } else {
                    RedactedSample(sample: PreviewSamples.title)
                }
            }
            .font(.title2.bold())
            .lineLimit(1)
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                MockDetailsCaption()
                VStack(alignment: .leading, spacing: 0) {
                    if let before = context.fieldsBefore.last {
                        detailRow(label: before.displayName) { RedactedSample() }
                            .accessibilityHidden(true)
                        Divider()
                    }
                    detailRow(label: label) { displayedValue }
                        .highlighted()
                    if let after = context.fieldsAfter.first {
                        Divider()
                        detailRow(label: after.displayName) { RedactedSample() }
                            .accessibilityHidden(true)
                    }
                }
                .mockCard(fill: cardFill)
            }
        }
    }

    private func detailRow(label: String, @ViewBuilder value: () -> some View) -> some View {
        MockDetailRow(label: label, layout: context.layoutOptions.detailLabelLayout, value: value)
    }

    // MARK: - Item List

    /// Where `ItemRowView` puts the field, if anywhere.
    private enum ListPlacement {
        case title, summaryLine, statusChip, badge, iconlessFlag, hidden
    }

    private var listPlacement: ListPlacement {
        if displayRole == .statusTabs { return .statusChip }
        if badgeIcon != nil { return .badge }
        if displayRole == .flagFilter { return .iconlessFlag }
        let index = context.fieldsBefore.count(where: \.isSummaryField)
        if index == 0 { return .title }
        return index <= Self.summaryLineCount ? .summaryLine : .hidden
    }

    private var itemListScreen: some View {
        VStack(alignment: .leading, spacing: AppConstants.ItemCard.rowSpacing) {
            if displayRole == .flagFilter {
                toolbarPreview
            }
            sampleListRow
            if let note = listNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var listNote: LocalizedStringKey? {
        switch listPlacement {
        case .hidden:
            "Only the first three fields show in the list. Move \(label) higher in the catalogue's fields to show it."
        case .badge where !boolValue:
            "The icon shows on items where \(label) is on."
        case .iconlessFlag:
            "Choose an icon to mark \(label) items in the list."
        default:
            nil
        }
    }

    private var sampleListRow: some View {
        MockListRow(showsThumbnail: context.layoutOptions.showPhotosInList, fill: cardFill) {
            MockThumbnail()
        } title: {
            if listPlacement == .title {
                Text(titleText.isEmpty ? String(localized: "Untitled Item") : titleText)
                    .highlighted()
            } else {
                RedactedSample(sample: PreviewSamples.title)
            }
        } lines: {
            summaryLines
        } trailing: {
            if listPlacement == .badge, boolValue {
                flagIcon
                    .font(.caption)
            }
            if listPlacement == .statusChip {
                statusChip
            }
        }
    }

    /// `nil` stands for the field being edited.
    private var summaryLineFields: [FieldDefinitionDraft?] {
        let before: [FieldDefinitionDraft?] = context.fieldsBefore.filter(\.isSummaryField)
        let own: [FieldDefinitionDraft?] = isSummaryField ? [nil] : []
        let after: [FieldDefinitionDraft?] = context.fieldsAfter.filter(\.isSummaryField)
        return Array((before + own + after).dropFirst().prefix(Self.summaryLineCount))
    }

    @ViewBuilder
    private var summaryLines: some View {
        ForEach(Array(summaryLineFields.enumerated()), id: \.offset) { _, field in
            if let field {
                HStack(spacing: 4) {
                    Text(verbatim: "\(field.displayName):")
                    RedactedSample()
                }
                .accessibilityHidden(true)
            } else if !titleText.isEmpty {
                // `ItemRowView` drops an empty value's line.
                Text(verbatim: "\(label): \(titleText)")
                    .highlighted()
            }
        }
    }

    /// A lone flag is a toolbar button of its own, labelled with the field's icon.
    private var toolbarPreview: some View {
        HStack {
            Spacer()
            flagIcon
                .foregroundStyle(.primary)
                .frame(width: 44, height: 36)
                .background(.background, in: .capsule)
        }
    }

    private var flagIcon: some View {
        Image(systemName: trimmedLabel(booleanOptions.flagIconName) ?? BooleanOptions.fallbackFilterIconName)
            .symbolVariant(.fill)
            .foregroundStyle(flagColor ?? .accentColor)
            .accessibilityLabel(label)
    }

    // MARK: - Field Value

    /// The value as text, for the title and summary lines.
    private var titleText: String {
        switch fieldType {
        case .text, .optionList:
            textValue
        case .number:
            numberValue.map { FieldValueFormatter.number($0, options: numberOptions) } ?? ""
        case .date:
            dateValue.map { FieldValueFormatter.date($0) } ?? ""
        case .boolean:
            booleanOptions.label(for: boolValue)
        }
    }

    @ViewBuilder
    private var displayedValue: some View {
        if displayRole == .statusTabs {
            statusChip
        } else if let badgeIcon {
            BooleanValueLabel(icon: badgeIcon, color: flagColor, isOn: boolValue, text: titleText)
        } else if titleText.isEmpty {
            MockEmptyValue()
        } else {
            Text(titleText)
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        switch fieldType {
        case .boolean:
            FieldChipView(text: titleText, tint: StatusChipPalette.booleanTint(isTrue: boolValue))
        case .optionList where !textValue.isEmpty:
            FieldChipView(
                text: textValue,
                tint: StatusChipPalette.tint(optionIndex: optionListOptions.options.firstIndex(of: textValue))
            )
        default:
            MockEmptyValue()
        }
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
        // An icon only shows when set, so start there whatever the default.
        boolValue = badgeIcon != nil || displayRole == .flagFilter || booleanOptions.defaultValue

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

private let previewNeighbours: FieldPreviewContext = {
    var context = FieldPreviewContext()
    context.fieldsBefore = [
        FieldDefinitionDraft(name: "Model", fieldType: .text, priority: 0),
        FieldDefinitionDraft(name: "Manufacturer", fieldType: .text, priority: 1),
    ]
    context.fieldsAfter = [FieldDefinitionDraft(name: "Scale", fieldType: .text, priority: 3)]
    context.tint = .orange
    return context
}()

#Preview("Field Previews") {
    Form {
        FieldPreviewSection(name: "Kit Number", fieldType: .text, context: previewNeighbours)
        FieldPreviewSection(
            name: "Purchase Price",
            fieldType: .number,
            numberOptions: NumberOptions(format: .currency, precision: 2),
            context: previewNeighbours
        )
        FieldPreviewSection(
            name: "Condition",
            fieldType: .optionList,
            optionListOptions: OptionListOptions(options: ["Mint", "Good", "Damaged"], defaultValue: "Good"),
            displayRole: .statusTabs,
            context: previewNeighbours
        )
        FieldPreviewSection(
            name: "Wishlist",
            fieldType: .boolean,
            booleanOptions: BooleanOptions(defaultValue: false, flagIconName: "star.fill", flagColorHex: "#FFCC00"),
            displayRole: .flagFilter,
            context: previewNeighbours
        )
        FieldPreviewSection(name: "Model", fieldType: .text)
    }
}
