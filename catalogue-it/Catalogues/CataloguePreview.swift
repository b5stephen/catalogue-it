//
//  CataloguePreview.swift
//  catalogue-it
//

import SwiftUI
import SwiftData

// MARK: - Preview Item

/// A stored value, read once when the sheet opens so redraws don't fault the item.
enum PreviewFieldValue: Equatable {
    case text(String)
    case number(Double)
    case date(Date)
    case bool(Bool)
}

/// An existing item, shown through the form's drafts so renames, reorders and option changes
/// apply before saving.
struct CataloguePreviewItem: Identifiable {
    let item: CatalogueItem
    /// By `FieldDefinition` ID; a field with no value is absent.
    let values: [PersistentIdentifier: PreviewFieldValue]

    var id: PersistentIdentifier { item.persistentModelID }

    init(item: CatalogueItem, definitions: [FieldDefinition]) {
        self.item = item
        var values: [PersistentIdentifier: PreviewFieldValue] = [:]
        for definition in definitions {
            guard let fieldValue = item.value(for: definition) else { continue }
            let value: PreviewFieldValue? = switch fieldValue.fieldType {
            case .text, .optionList:
                fieldValue.textValue.flatMap { $0.isEmpty ? nil : .text($0) }
            case .number:
                fieldValue.numberValue.map { .number($0) }
            case .date:
                fieldValue.dateValue.map { .date($0) }
            case .boolean:
                .bool(fieldValue.boolValue == true)
            }
            values[definition.persistentModelID] = value
        }
        self.values = values
    }

    /// The most recently added, fetched with a limit so a large catalogue costs the same.
    static func recent(in catalogue: Catalogue, context: ModelContext, limit: Int = 3) -> [CataloguePreviewItem] {
        let catalogueID = catalogue.persistentModelID
        var descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID && $0.deletedDate == nil },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let definitions = catalogue.sortedFieldDefinitions
        return ((try? context.fetch(descriptor)) ?? []).map { CataloguePreviewItem(item: $0, definitions: definitions) }
    }
}

// MARK: - Preview Model

/// What the item screens would show for the form's current drafts. Fields are normalised as the
/// save will, so an unsupported or second status role shows as it will end up.
struct CataloguePreviewModel {
    let fields: [FieldDefinitionDraft]
    let items: [CataloguePreviewItem]
    let layoutOptions: CatalogueLayoutOptions
    let showAllTab: Bool
    let tint: Color

    static let summaryLineCount = 2

    init(
        drafts: [FieldDefinitionDraft],
        items: [CataloguePreviewItem],
        layoutOptions: CatalogueLayoutOptions,
        showAllTab: Bool,
        tint: Color
    ) {
        fields = FieldDefinitionValidation.normalised(drafts)
        self.items = items
        self.layoutOptions = layoutOptions
        self.showAllTab = showAllTab
        self.tint = tint
    }

    /// A field's value as one item's screens show it.
    enum Shown {
        case text(String)
        /// A text sample, which has no meaningful value to show.
        case redacted
        case missing
    }

    var cardFill: CardFill {
        CardFill(colorHex: tint.toHex())
    }

    var summaryFields: [FieldDefinitionDraft] {
        fields.filter(\.isSummaryField)
    }

    var statusDraft: FieldDefinitionDraft? {
        fields.first { $0.displayRole == .statusTabs }
    }

    var statusTabs: [StatusTabDescriptor] {
        guard let statusDraft else { return [] }
        return StatusTabDescriptor.tabs(
            fieldType: statusDraft.fieldType,
            options: statusDraft.optionListOptions.options,
            booleanLabels: statusDraft.booleanOptions.resolvedLabels,
            showAllTab: showAllTab
        )
    }

    // MARK: Values

    /// An existing item shows what it holds; a new field, or a catalogue with no items, a sample.
    func value(of field: FieldDefinitionDraft, in item: CataloguePreviewItem?) -> PreviewFieldValue? {
        guard let item, let definition = field.existingDefinition else { return sample(for: field) }
        guard let stored = item.values[definition.persistentModelID] else { return nil }
        switch (field.fieldType, stored) {
        case (.text, .text), (.number, .number), (.date, .date), (.boolean, .bool):
            return stored
        case (.optionList, .text(let option)):
            if field.pendingOptionDeletions.contains(option) { return nil }
            return .text(field.pendingOptionRenames[option] ?? option)
        default:
            // The field's type changed in this form.
            return nil
        }
    }

    func shown(_ field: FieldDefinitionDraft, in item: CataloguePreviewItem?) -> Shown {
        guard let value = value(of: field, in: item) else {
            let isSample = item == nil || field.existingDefinition == nil
            return isSample && (field.fieldType == .text || field.fieldType == .optionList) ? .redacted : .missing
        }
        let text = formatted(value, for: field)
        return text.isEmpty ? .missing : .text(text)
    }

    func isOn(_ field: FieldDefinitionDraft, in item: CataloguePreviewItem?) -> Bool {
        value(of: field, in: item) == .bool(true)
    }

    func chipTint(_ field: FieldDefinitionDraft, in item: CataloguePreviewItem?) -> Color {
        switch value(of: field, in: item) {
        case .text(let option):
            StatusChipPalette.tint(optionIndex: field.optionListOptions.options.firstIndex(of: option))
        case .bool(let isOn):
            StatusChipPalette.booleanTint(isTrue: isOn)
        default:
            .secondary
        }
    }

    private func formatted(_ value: PreviewFieldValue, for field: FieldDefinitionDraft) -> String {
        switch value {
        case .text(let text): text
        case .number(let number): FieldValueFormatter.number(number, options: field.numberOptions)
        case .date(let date): FieldValueFormatter.date(date)
        case .bool(let isOn): field.booleanOptions.label(for: isOn)
        }
    }

    /// Text has no meaningful sample, so it is redacted instead.
    private func sample(for field: FieldDefinitionDraft) -> PreviewFieldValue? {
        switch field.fieldType {
        case .text:
            return nil
        case .number:
            return .number(1234.5)
        case .date:
            return .date(.now)
        case .optionList:
            let options = field.optionListOptions
            let option = options.defaultValue.flatMap { options.options.contains($0) ? $0 : nil }
                ?? options.options.sorted().first
            return option.map { .text($0) }
        case .boolean:
            // An icon only shows when set.
            return .bool(field.showsIconBadge || field.displayRole == .flagFilter || field.booleanOptions.defaultValue)
        }
    }
}

// MARK: - Preview Row

/// One item as `ItemRowView` shows it.
struct CataloguePreviewRow: View {
    let model: CataloguePreviewModel
    let item: CataloguePreviewItem?
    var showsStatusChip = true

    var body: some View {
        MockListRow(showsThumbnail: model.layoutOptions.showPhotosInList, fill: model.cardFill) {
            if let item {
                ItemThumbnailView(key: ThumbnailKey(item: item.item))
            } else {
                MockThumbnail()
            }
        } title: {
            title
        } lines: {
            ForEach(summaryLines, id: \.field.id) { line in
                switch line.shown {
                case .text(let text):
                    Text(verbatim: "\(line.field.displayName): \(text)")
                case .redacted:
                    HStack(spacing: 4) {
                        Text(verbatim: "\(line.field.displayName):")
                        RedactedSample()
                    }
                case .missing:
                    EmptyView()
                }
            }
        } trailing: {
            ForEach(model.fields.filter { $0.showsIconBadge && model.isOn($0, in: item) }) { flag in
                if let icon = flag.flagIconName {
                    Image(systemName: icon)
                        .symbolVariant(.fill)
                        .foregroundStyle(flag.flagColor ?? .accentColor)
                        .font(.caption)
                        .accessibilityLabel(flag.displayName)
                }
            }
            if showsStatusChip, let status = model.statusDraft, case .text(let label) = model.shown(status, in: item) {
                FieldChipView(text: label, tint: model.chipTint(status, in: item))
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        if let field = model.summaryFields.first {
            switch model.shown(field, in: item) {
            case .text(let text):
                Text(text)
            case .redacted:
                // As the edit sheet shows an empty field.
                Text(field.displayName)
                    .foregroundStyle(.tertiary)
            case .missing:
                Text("Untitled Item")
            }
        } else {
            Text("Untitled Item")
        }
    }

    private var summaryLines: [(field: FieldDefinitionDraft, shown: CataloguePreviewModel.Shown)] {
        model.summaryFields
            .dropFirst()
            .prefix(CataloguePreviewModel.summaryLineCount)
            .map { ($0, model.shown($0, in: item)) }
    }
}

// MARK: - Inline Section

/// The list row on the catalogue form, opening the full preview.
struct CataloguePreviewSection: View {
    let model: CataloguePreviewModel
    let onOpen: () -> Void

    var body: some View {
        Section {
            Button(action: onOpen) {
                CataloguePreviewRow(model: model, item: model.items.first)
                    .mockScreen(tint: model.tint)
                    .contentShape(MockScreen.shape)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows more items and the item page")
            .previewRow()
        } header: {
            HStack {
                Text("Preview")
                Spacer()
                Button("More", action: onOpen)
                    .font(.caption)
                    .textCase(nil)
            }
        }
    }
}

// MARK: - Preview Page

struct CataloguePreviewView: View {
    let model: CataloguePreviewModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: AppConstants.ItemCard.rowSpacing) {
                    itemListScreen
                }
                .mockScreen(tint: model.tint)
                .previewRow()
            } header: {
                Text("List View Card")
            }

            Section {
                itemPageScreen
                    .mockScreen(tint: model.tint)
                    .previewRow()
            } header: {
                Text("Detail View Card")
            }
        }
        .navigationTitle("Preview")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    // MARK: Item List

    /// The list starts on its first tab, and shows chips only on "All".
    private var itemListScreen: some View {
        let tabs = model.statusTabs
        let showsChips = tabs.first?.tab == .all
        return Group {
            if let first = tabs.first {
                StatusTabBar(tabs: tabs, colorHex: model.tint.toHex(), selection: .constant(first.tab))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if model.items.isEmpty {
                CataloguePreviewRow(model: model, item: nil, showsStatusChip: showsChips)
            } else {
                ForEach(model.items) { item in
                    CataloguePreviewRow(model: model, item: item, showsStatusChip: showsChips)
                }
            }
        }
    }

    // MARK: Item Page

    private var pageItem: CataloguePreviewItem? { model.items.first }

    /// Mirrors `ItemDetailView`, which leaves out empty fields.
    private var itemPageScreen: some View {
        let rows = model.fields.filter {
            if case .missing = model.shown($0, in: pageItem) { return false }
            return true
        }
        return VStack(alignment: .leading, spacing: 12) {
            pageTitle
                .font(.title2.bold())
                .lineLimit(1)
                .padding(.horizontal, 4)

            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    MockDetailsCaption()
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, field in
                            if index > 0 { Divider() }
                            MockDetailRow(label: field.displayName, layout: model.layoutOptions.detailLabelLayout) {
                                detailValue(field)
                            }
                        }
                    }
                    .mockCard(fill: model.cardFill)
                }
            }
        }
    }

    @ViewBuilder
    private var pageTitle: some View {
        if let field = model.fields.first {
            switch model.shown(field, in: pageItem) {
            case .text(let text):
                Text(text)
            case .redacted:
                Text(field.displayName)
                    .foregroundStyle(.tertiary)
            case .missing:
                Text("Untitled Item")
            }
        } else {
            Text("Untitled Item")
        }
    }

    @ViewBuilder
    private func detailValue(_ field: FieldDefinitionDraft) -> some View {
        let shown = model.shown(field, in: pageItem)
        if field.displayRole == .statusTabs {
            if case .text(let label) = shown {
                FieldChipView(text: label, tint: model.chipTint(field, in: pageItem))
            } else {
                MockEmptyValue()
            }
        } else if field.showsIconBadge, let icon = field.flagIconName, case .text(let label) = shown {
            BooleanValueLabel(icon: icon, color: field.flagColor, isOn: model.isOn(field, in: pageItem), text: label)
        } else {
            switch shown {
            case .text(let text): Text(text)
            case .redacted: RedactedSample()
            case .missing: MockEmptyValue()
            }
        }
    }
}

// MARK: - Row Styling

private extension View {
    /// Off the form's own row chrome, so the mock reads as a screen rather than a setting.
    func previewRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }
}

// MARK: - Preview

private let previewModel = CataloguePreviewModel(
    drafts: [
        FieldDefinitionDraft(name: "Model", fieldType: .text, priority: 0),
        FieldDefinitionDraft(name: "Manufacturer", fieldType: .text, priority: 1),
        FieldDefinitionDraft(
            name: "Price",
            fieldType: .number,
            priority: 2,
            numberOptions: NumberOptions(format: .currency, precision: 2)
        ),
        FieldDefinitionDraft(name: "Year", fieldType: .number, priority: 3),
        FieldDefinitionDraft(
            name: "Condition",
            fieldType: .optionList,
            priority: 4,
            displayRole: .statusTabs,
            optionListOptions: OptionListOptions(options: ["Mint", "Good", "Damaged"], defaultValue: "Good")
        ),
        FieldDefinitionDraft(
            name: "Favourite",
            fieldType: .boolean,
            priority: 5,
            booleanOptions: BooleanOptions(flagIconName: "heart", flagColorHex: "#FF2D55")
        ),
    ],
    items: [],
    layoutOptions: CatalogueLayoutOptions(),
    showAllTab: true,
    tint: .orange
)

#Preview("Catalogue Preview") {
    NavigationStack {
        Form {
            CataloguePreviewSection(model: previewModel) {}
        }
    }
}

#Preview("Catalogue Preview Page") {
    NavigationStack {
        CataloguePreviewView(model: previewModel)
    }
}
