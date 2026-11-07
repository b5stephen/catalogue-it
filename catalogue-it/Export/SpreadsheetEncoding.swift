//
//  SpreadsheetEncoding.swift
//  catalogue-it
//

import Foundation

// MARK: - Spreadsheet Encoding

/// Pure cell and row encoding for the Spreadsheet format, shared by the file writer, Copy and
/// the composer's preview so all three agree.
nonisolated enum SpreadsheetEncoding {

    enum ValueStyle: Hashable, CaseIterable, Sendable {
        /// ISO dates and plain numbers, which a spreadsheet parses without guessing a locale.
        case forSpreadsheet
        /// Exactly what the app shows.
        case asShown
    }

    struct Options: Equatable, Sendable {
        var valueStyle = ValueStyle.forSpreadsheet
        var includesHeader = true
    }

    enum RowFormat: Sendable {
        /// RFC 4180, CRLF.
        case csv
        /// For pasting: a tab or line break inside a cell would split it across cells.
        case tsv
    }

    /// A column resolved against the definitions of one context.
    enum Column {
        case field(FieldDefinition)
        case notes
        case dateAdded
        case photoCount

        var title: String {
            switch self {
            case .field(let definition): definition.name
            case .notes: ExportColumn.notes.itemInfoTitle ?? ""
            case .dateAdded: ExportColumn.dateAdded.itemInfoTitle ?? ""
            case .photoCount: ExportColumn.photoCount.itemInfoTitle ?? ""
            }
        }
    }

    static let byteOrderMark = "\u{FEFF}"

    // MARK: Columns

    /// Fields in `FieldDefinition.isOrderedBefore` order, then Notes, Date Added and Photo Count,
    /// whatever order `chosen` lists them in. A field that no longer exists is dropped.
    static func columns(_ chosen: [ExportColumn], in definitions: [FieldDefinition]) -> [Column] {
        let wanted = Set(chosen)
        var columns = definitions
            .sorted(by: FieldDefinition.isOrderedBefore)
            .filter { wanted.contains(.field($0.fieldID)) }
            .map(Column.field)
        if wanted.contains(.notes) { columns.append(.notes) }
        if wanted.contains(.dateAdded) { columns.append(.dateAdded) }
        if wanted.contains(.photoCount) { columns.append(.photoCount) }
        return columns
    }

    // MARK: Rows

    static func headerCells(for columns: [Column]) -> [String] {
        columns.map(\.title)
    }

    /// `photoCount` is passed in so the caller decides how to count without faulting `photos`.
    static func cells(
        for item: CatalogueItem,
        columns: [Column],
        photoCount: Int,
        style: ValueStyle
    ) -> [String] {
        columns.map { cell(for: $0, item: item, photoCount: photoCount, style: style) }
    }

    static func cell(for column: Column, item: CatalogueItem, photoCount: Int, style: ValueStyle) -> String {
        switch column {
        case .field(let definition):
            return fieldCell(definition, item: item, style: style)
        case .notes:
            return item.notes ?? ""
        case .dateAdded:
            return style == .forSpreadsheet ? isoDate(item.createdDate) : FieldValueFormatter.date(item.createdDate)
        case .photoCount:
            return String(photoCount)
        }
    }

    private static func fieldCell(_ definition: FieldDefinition, item: CatalogueItem, style: ValueStyle) -> String {
        guard style == .forSpreadsheet else { return item.displayValue(for: definition) }
        switch definition.fieldType {
        case .text, .optionList:
            return item.value(for: definition)?.textValue ?? ""
        case .number:
            return item.value(for: definition)?.numberValue.map(plainNumber) ?? ""
        case .date:
            return item.value(for: definition)?.dateValue.map { isoDate($0) } ?? ""
        case .boolean:
            return item.displayValue(for: definition)
        }
    }

    static func row(_ cells: [String], as format: RowFormat) -> String {
        switch format {
        case .csv: cells.map(csvCell).joined(separator: ",") + "\r\n"
        case .tsv: cells.map(tsvCell).joined(separator: "\t") + "\n"
        }
    }

    // MARK: Cells

    static func csvCell(_ text: String) -> String {
        // Scalars, not Characters: "\r\n" is one Character, equal to neither "\r" nor "\n".
        guard text.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// `\r\n` is a single Character in Swift, so the loop replaces it as one space.
    static func tsvCell(_ text: String) -> String {
        guard text.contains(where: { $0 == "\t" || $0.isNewline }) else { return text }
        return String(text.map { $0 == "\t" || $0.isNewline ? " " : $0 })
    }

    // MARK: Values

    /// The date as the user's calendar day, so it matches what the app shows.
    static func isoDate(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Shortest representation that round-trips, in plain notation: `.` decimal, no grouping,
    /// no exponent, no trailing `.0`. Empty for NaN and infinity.
    static func plainNumber(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == 0 { return "0" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        let shortest = value.description
        guard shortest.contains("e") else { return shortest }
        return Decimal(string: shortest).map { "\($0)" } ?? shortest
    }

    // MARK: File Name

    /// `"<Catalogue>.csv"`, or `"<Catalogue> – Filtered.csv"`.
    static func fileName(catalogueName: String, filtered: Bool) -> String {
        let name = catalogueName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return (filtered ? "\(name) – Filtered" : name) + ".csv"
    }
}
