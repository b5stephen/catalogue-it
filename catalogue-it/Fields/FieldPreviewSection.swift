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
/// summary lines from the role-less fields; status chip and flags trailing) — keep it in step.
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

    private static let screenPadding: CGFloat = 10
    /// Outer = card + padding, so the mock cards sit concentric in the screen (card-design skill).
    private static let screenCornerRadius = AppConstants.CornerRadius.card + screenPadding
    private static let summaryLineCount = 2

    enum PreviewScreen: CaseIterable, Identifiable {
        case adding, itemPage, itemList
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .adding: "Adding"
            case .itemPage: "Item Page"
            case .itemList: "Item List"
            }
        }
    }

    /// The name row's placeholder, for a field not yet named.
    private var label: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Field Name") : trimmed
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
            "Try a value here — the other previews show it."
        case .itemPage:
            "How the field reads on an item's page. Other fields' values are placeholders."
        case .itemList:
            "How the field shows on an item in the list. Other fields' values are placeholders."
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
        .padding(Self.screenPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(context.tint.opacity(0.08), in: screenShape)
        .overlay { screenShape.strokeBorder(.separator) }
        .tint(context.tint)
    }

    /// The real cards' fill, which in dark is a deep shade of the catalogue's colour.
    private var cardFill: CardFill {
        CardFill(colorHex: context.tint.toHex())
    }

    private var screenShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.screenCornerRadius, style: .continuous)
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
                    placeholderText(PreviewSamples.title)
                }
            }
            .font(.title2.bold())
            .lineLimit(1)
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.tint)
                    .padding(.leading, 4)
                VStack(alignment: .leading, spacing: 0) {
                    if let before = context.fieldsBefore.last {
                        detailRow(label: before.displayName) { placeholderText(PreviewSamples.value) }
                            .accessibilityHidden(true)
                        Divider()
                    }
                    detailRow(label: label) { displayedValue }
                        .highlighted()
                    if let after = context.fieldsAfter.first {
                        Divider()
                        detailRow(label: after.displayName) { placeholderText(PreviewSamples.value) }
                            .accessibilityHidden(true)
                    }
                }
                .mockCard(fill: cardFill)
            }
        }
    }

    /// Mirrors `FieldRowView` and `StatusFieldRowView`.
    @ViewBuilder
    private func detailRow(label: String, @ViewBuilder value: () -> some View) -> some View {
        switch context.layoutOptions.detailLabelLayout {
        case .beside:
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                value()
            }
            .padding(.vertical, 10)
        case .above:
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                value()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Item List

    /// Where `ItemRowView` puts the field, if anywhere.
    private enum ListPlacement {
        case title, summaryLine, statusChip, flag, hidden
    }

    private var listPlacement: ListPlacement {
        switch displayRole {
        case .statusTabs: return .statusChip
        case .flagFilter: return .flag
        case .none:
            let index = context.fieldsBefore.count(where: { $0.displayRole == .none })
            if index == 0 { return .title }
            return index <= Self.summaryLineCount ? .summaryLine : .hidden
        }
    }

    private var itemListScreen: some View {
        VStack(alignment: .leading, spacing: AppConstants.ItemCard.rowSpacing) {
            if listPlacement == .flag {
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
        case .flag where !boolValue:
            "The icon shows on items where \(label) is on."
        default:
            nil
        }
    }

    private var sampleListRow: some View {
        HStack(spacing: 12) {
            if context.layoutOptions.showPhotosInList {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
                    .frame(width: AppConstants.ThumbnailSize.list, height: AppConstants.ThumbnailSize.list)
                    .background(
                        .fill.tertiary,
                        in: .rect(cornerRadius: AppConstants.ItemCard.thumbnailCornerRadius, style: .continuous)
                    )
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if listPlacement == .title {
                        Text(titleText.isEmpty ? String(localized: "Untitled Item") : titleText)
                            .highlighted()
                    } else {
                        placeholderText(PreviewSamples.title)
                    }
                }
                .font(.headline)
                .lineLimit(1)

                summaryLines
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minHeight: AppConstants.ThumbnailSize.list, alignment: .leading)
            Spacer(minLength: 0)
            if listPlacement == .flag, boolValue {
                flagIcon
                    .font(.caption)
            }
            if listPlacement == .statusChip {
                statusChip
            }
        }
        .padding(AppConstants.ItemCard.contentPadding)
        .background(cardFill, in: .rect(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
    }

    /// `nil` stands for the field being edited.
    private var summaryLineFields: [FieldDefinitionDraft?] {
        let before: [FieldDefinitionDraft?] = context.fieldsBefore.filter { $0.displayRole == .none }
        let own: [FieldDefinitionDraft?] = displayRole == .none ? [nil] : []
        let after: [FieldDefinitionDraft?] = context.fieldsAfter.filter { $0.displayRole == .none }
        return Array((before + own + after).dropFirst().prefix(Self.summaryLineCount))
    }

    @ViewBuilder
    private var summaryLines: some View {
        ForEach(Array(summaryLineFields.enumerated()), id: \.offset) { _, field in
            if let field {
                HStack(spacing: 4) {
                    Text(verbatim: "\(field.displayName):")
                    placeholderText(PreviewSamples.value)
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
            displayRole == .statusTabs ? booleanStatusLabel : FieldValueFormatter.boolean(boolValue)
        }
    }

    @ViewBuilder
    private var displayedValue: some View {
        if displayRole == .statusTabs {
            statusChip
        } else if titleText.isEmpty {
            emptyPlaceholder
        } else {
            Text(titleText)
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        switch fieldType {
        case .boolean:
            FieldChipView(text: booleanStatusLabel, tint: StatusChipPalette.booleanTint(isTrue: boolValue))
        case .optionList where !textValue.isEmpty:
            FieldChipView(
                text: textValue,
                tint: StatusChipPalette.tint(optionIndex: optionListOptions.options.firstIndex(of: textValue))
            )
        default:
            emptyPlaceholder
        }
    }

    private var booleanStatusLabel: String {
        boolValue
            ? trimmedLabel(booleanOptions.trueLabel) ?? String(localized: "Yes")
            : trimmedLabel(booleanOptions.falseLabel) ?? String(localized: "No")
    }

    private var emptyPlaceholder: some View {
        Text(verbatim: "—")
            .foregroundStyle(.tertiary)
    }

    private func placeholderText(_ sample: String) -> some View {
        Text(verbatim: sample)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
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
        // A flag's icon only shows when set, so start there whatever the default.
        boolValue = displayRole == .flagFilter || booleanOptions.defaultValue

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

// MARK: - Samples

/// Lengths for the redacted placeholders; never shown as text.
private enum PreviewSamples {
    static let title = "Sample item name"
    static let value = "Sample"
}

// MARK: - Mock Styling

private extension View {
    /// A `CatalogueSectionCard`-style card inside the mock screen.
    func mockCard(fill: CardFill) -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
    }

    /// Marks the field being edited among its placeholder neighbours. Rows and lines only: a
    /// chip or icon is already the only real value in its row, and a halo crowds it.
    func highlighted() -> some View {
        background {
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.small, style: .continuous)
                .fill(.tint.opacity(0.14))
                .padding(.horizontal, -6)
                .padding(.vertical, 2)
        }
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
