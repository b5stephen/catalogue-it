//
//  ItemShareText.swift
//  catalogue-it
//

import Foundation

// MARK: - Item Share Text

/// The Message format, and the rows on a card. Pure: the caller decides what to do with the string.
enum ItemShareText {

    struct Options {
        var showFieldNames = true
        /// Skips empty values and Yes/No fields that are off.
        var leaveOutBlanks = true
    }

    struct Entry: Equatable {
        let label: String
        let value: String
    }

    private static let blankPlaceholder = "–"

    // MARK: Text

    /// `columns` is the ticked set; the title column is always read from the first field.
    static func text(
        for items: [CatalogueItem],
        in catalogue: Catalogue,
        columns: Set<ExportColumn>,
        options: Options = Options()
    ) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return singleItemText(items[0], in: catalogue, columns: columns, options: options)
        default:
            let count = String(localized: "\(items.count) items")
            var lines = ["\(catalogue.name) · \(count)"]
            for item in items {
                let values = entries(for: item, in: catalogue, columns: columns, leaveOutBlanks: options.leaveOutBlanks)
                    .map { oneLine($0.value) }
                let title = title(for: item, in: catalogue)
                lines.append(values.isEmpty ? "• \(title)" : "• \(title) — \(values.joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")
        }
    }

    private static func singleItemText(
        _ item: CatalogueItem,
        in catalogue: Catalogue,
        columns: Set<ExportColumn>,
        options: Options
    ) -> String {
        let entries = entries(for: item, in: catalogue, columns: columns, leaveOutBlanks: options.leaveOutBlanks)
        var lines = [title(for: item, in: catalogue)]
        if options.showFieldNames {
            lines.append(contentsOf: entries.map { "\($0.label): \($0.value)" })
        } else if !entries.isEmpty {
            lines.append(entries.map { oneLine($0.value) }.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Content

    /// The first field's value.
    static func title(for item: CatalogueItem, in catalogue: Catalogue) -> String {
        guard let first = catalogue.sortedFieldDefinitions.first else { return untitled }
        let text = item.displayValue(for: first).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? untitled : text
    }

    private static var untitled: String { String(localized: "Untitled Item") }

    /// The ticked columns after the title, in field order and then Notes. A blank value shows as a
    /// dash when `leaveOutBlanks` is off.
    static func entries(
        for item: CatalogueItem,
        in catalogue: Catalogue,
        columns: Set<ExportColumn>,
        leaveOutBlanks: Bool
    ) -> [Entry] {
        var entries: [Entry] = []
        for definition in catalogue.sortedFieldDefinitions.dropFirst() where columns.contains(.field(definition.fieldID)) {
            let isBlank = definition.fieldType == .boolean
                ? !item.isOn(definition)
                : item.displayValue(for: definition).isBlank
            if leaveOutBlanks && isBlank { continue }
            entries.append(Entry(label: definition.name, value: value(item.displayValue(for: definition))))
        }
        if columns.contains(.notes) {
            let notes = item.notes ?? ""
            if !(leaveOutBlanks && notes.isBlank) {
                entries.append(Entry(label: ExportColumn.notes.title(in: catalogue), value: value(notes)))
            }
        }
        return entries
    }

    private static func value(_ text: String) -> String {
        text.isBlank ? blankPlaceholder : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
