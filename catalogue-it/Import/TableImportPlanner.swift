//
//  TableImportPlanner.swift
//  catalogue-it
//

import Foundation

// MARK: - Column Target

nonisolated enum ColumnTarget: Hashable, Sendable {
    case skip
    case notes
    case dateAdded
    case field(UUID)
    case newField(FieldType)

    /// Notes, Date Added and an existing field take at most one column each.
    var isExclusive: Bool {
        switch self {
        case .notes, .dateAdded, .field: true
        case .skip, .newField: false
        }
    }
}

// MARK: - Target Field

/// What the planner needs of a field in the catalogue being imported into.
nonisolated struct TargetField: Equatable, Sendable {
    let fieldID: UUID
    let name: String
    let fieldType: FieldType
    var options: [String] = []
    var trueLabel: String?
    var falseLabel: String?
}

nonisolated extension TargetField {
    init(_ definition: FieldDefinition) {
        fieldID = definition.fieldID
        name = definition.name
        fieldType = definition.fieldType
        options = definition.optionListOptions?.options ?? []
        trueLabel = definition.booleanOptions?.trueLabel
        falseLabel = definition.booleanOptions?.falseLabel
    }
}

// MARK: - Column Summary

nonisolated struct ColumnSummary: Identifiable, Equatable, Sendable {
    let index: Int
    let header: String
    /// The first few non-empty values, for the mapping row.
    let samples: [String]
    let inferredType: FieldType

    var id: Int { index }
}

// MARK: - Column Check

/// Values in a column that its target can't take. They are left empty.
nonisolated struct ColumnCheck: Equatable, Sendable {
    var unreadableCount = 0
    var examples: [String] = []
    /// For an existing option-list field: values it doesn't list yet, which import adds.
    var newOptions: [String] = []
}

// MARK: - Table Import Planner

/// Turns a spreadsheet into a Data file's catalogue, so `ItemImporter` writes it exactly as it
/// writes a backup. Pure apart from the parser's formatters.
nonisolated enum TableImportPlanner {

    static let maxSamples = 3
    /// Above this many distinct values a column is text rather than an option list.
    static let maxInferredOptions = 20

    // MARK: Columns

    static func headers(of table: ImportTable, hasHeaderRow: Bool) -> [String] {
        (0..<table.columnCount).map { index in
            let header = hasHeaderRow ? table.rows[0][index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return header.isEmpty ? String(localized: "Column \(index + 1)") : header
        }
    }

    static func dataRows(of table: ImportTable, hasHeaderRow: Bool) -> ArraySlice<[String]> {
        hasHeaderRow ? table.rows.dropFirst() : table.rows[...]
    }

    /// A first row whose every cell is text while some column below it reads as a number, date
    /// or Yes/No is a header row. With no such column, a first row with no repeats is taken
    /// as one, which is how most sheets start.
    static func guessHasHeaderRow(_ table: ImportTable, parser: ImportValueParser) -> Bool {
        guard table.rows.count > 1 else { return false }
        let first = table.rows[0]
        let typed = summarise(table, hasHeaderRow: true, parser: parser)
        for summary in typed where summary.inferredType != .text && summary.inferredType != .optionList {
            let cell = first[summary.index]
            if !cell.isEmpty && inferType(of: [cell], parser: parser) == summary.inferredType { return false }
        }
        let nonEmpty = first.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Set(nonEmpty.map(ImportFieldMatcher.normalised)).count == nonEmpty.count && !nonEmpty.isEmpty
    }

    /// The day/month order the column values imply, when one is above 12; otherwise `nil`.
    static func impliedDateOrder(_ table: ImportTable, hasHeaderRow: Bool, parser: ImportValueParser) -> ImportDateOrder? {
        for row in dataRows(of: table, hasHeaderRow: hasHeaderRow) {
            for cell in row {
                guard let parts = parser.numericDateLeadingParts(cell) else { continue }
                if parts.first > 12 { return .dayMonthYear }
                if parts.second > 12 { return .monthDayYear }
            }
        }
        return nil
    }

    /// Whether any column holds numeric dates whose order the values don't settle.
    static func hasAmbiguousDates(_ table: ImportTable, hasHeaderRow: Bool, parser: ImportValueParser) -> Bool {
        dataRows(of: table, hasHeaderRow: hasHeaderRow).contains { row in
            row.contains { parser.numericDateLeadingParts($0) != nil }
        }
    }

    static func summarise(_ table: ImportTable, hasHeaderRow: Bool, parser: ImportValueParser) -> [ColumnSummary] {
        let headers = headers(of: table, hasHeaderRow: hasHeaderRow)
        let rows = dataRows(of: table, hasHeaderRow: hasHeaderRow)
        return headers.indices.map { index in
            let values = rows.map { $0[index].trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return ColumnSummary(
                index: index,
                header: headers[index],
                samples: Array(values.prefix(maxSamples)),
                inferredType: inferType(of: values, parser: parser)
            )
        }
    }

    /// Cells that stand for "no value" in a column of numbers, dates or Yes/No: left empty
    /// rather than counted as unreadable. A text column keeps them as written.
    static func isPlaceholder(_ cell: String) -> Bool {
        ["n/a", "na", "-", "–", "—", "?", "none", "tbc", "tbd", "unknown"].contains(ImportFieldMatcher.normalised(cell))
    }

    /// Every value bar placeholders must read as the type. A number with a leading zero (`007`)
    /// is a code, so text; a column of four or more values, at most half of them distinct, is an
    /// option list.
    static func inferType(of allValues: [String], parser: ImportValueParser) -> FieldType {
        let values = allValues.filter { !isPlaceholder($0) }
        guard !values.isEmpty else { return .text }
        if values.allSatisfy(parser.looksBoolean) { return .boolean }
        let hasLeadingZero = values.contains { $0.count > 1 && $0.hasPrefix("0") && !$0.hasPrefix("0.") && !$0.hasPrefix("0,") }
        if !hasLeadingZero, values.allSatisfy({ parser.number($0) != nil }) { return .number }
        if values.allSatisfy({ parser.date($0) != nil }) { return .date }
        let distinct = Set(allValues).count
        if allValues.count >= 4, distinct <= maxInferredOptions, distinct * 2 <= allValues.count {
            return .optionList
        }
        return .text
    }

    // MARK: Targets

    /// Notes and Date Added by name (as the app's own spreadsheet export heads them), Photo
    /// Count skipped, then existing fields by name; every other column a new field of its
    /// guessed type.
    static func defaultTargets(for columns: [ColumnSummary], existing: [TargetField]) -> [ColumnTarget] {
        var claimed = Set<ColumnTarget>()
        return columns.map { column in
            let key = ImportFieldMatcher.normalised(column.header)
            let target: ColumnTarget
            if key == ImportFieldMatcher.normalised(String(localized: "Notes")) {
                target = .notes
            } else if key == ImportFieldMatcher.normalised(String(localized: "Date Added")) {
                target = .dateAdded
            } else if key == ImportFieldMatcher.normalised(String(localized: "Photo Count")) {
                return .skip
            } else if let field = existing.first(where: { ImportFieldMatcher.normalised($0.name) == key }) {
                target = .field(field.fieldID)
            } else {
                return .newField(column.inferredType)
            }
            guard !claimed.contains(target) else { return .newField(column.inferredType) }
            claimed.insert(target)
            return target
        }
    }

    // MARK: Checking

    static func check(
        _ table: ImportTable,
        column index: Int,
        target: ColumnTarget,
        hasHeaderRow: Bool,
        existing: [TargetField],
        parser: ImportValueParser
    ) -> ColumnCheck {
        var check = ColumnCheck()
        let field = fieldTarget(target, existing: existing)
        for row in dataRows(of: table, hasHeaderRow: hasHeaderRow) {
            let cell = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cell.isEmpty, !(takesPlaceholders(field) && isPlaceholder(cell)) else { continue }
            switch read(cell, as: target, field: field, parser: parser) {
            case .some:
                if case .field = target, field?.fieldType == .optionList, let field,
                   canonicalOption(cell, in: field.options) == nil, !check.newOptions.contains(cell) {
                    check.newOptions.append(cell)
                }
            case .none:
                check.unreadableCount += 1
                if check.examples.count < maxSamples, !check.examples.contains(cell) { check.examples.append(cell) }
            }
        }
        return check
    }

    // MARK: Building

    struct Plan {
        var hasHeaderRow: Bool
        var targets: [ColumnTarget]
        /// The catalogue's name, when the import makes a new one.
        var catalogueName: String
        var colorHex: String
        var duplicateCheck: DuplicateCheck?
    }

    struct Built {
        let catalogue: CatalogueDTO
        /// Rows with nothing in any imported column.
        let skippedRowCount: Int
        /// Rows left out because `Plan.duplicateCheck` found them already in the catalogue.
        var duplicateRowCount = 0
    }

    // MARK: Duplicates

    /// Rows whose value in `column` matches one of `existingKeys` (the field's values on the
    /// catalogue's live items) are already there, and are left out.
    struct DuplicateCheck: Equatable {
        let column: Int
        let fieldType: FieldType
        let existingKeys: Set<String>
    }

    /// An option list is a category shared by many items, so it can't tell them apart.
    static func canMatchDuplicates(on fieldType: FieldType) -> Bool {
        fieldType == .text || fieldType == .number
    }

    /// Text compares ignoring case and accents; numbers by value, so `1,200` matches 1200.
    static func duplicateKey(_ cell: String, fieldType: FieldType, parser: ImportValueParser) -> String? {
        switch fieldType {
        case .number:
            return parser.number(cell).map { SpreadsheetEncoding.plainNumber($0.value) }
        case .text, .optionList:
            let key = ImportFieldMatcher.normalised(cell)
            return key.isEmpty ? nil : key
        case .date, .boolean:
            return nil
        }
    }

    static func duplicateKey(_ value: FieldValue) -> String? {
        switch value.fieldType {
        case .number:
            return value.numberValue.map(SpreadsheetEncoding.plainNumber)
        case .text, .optionList:
            let key = ImportFieldMatcher.normalised(value.textValue ?? "")
            return key.isEmpty ? nil : key
        case .date, .boolean:
            return nil
        }
    }

    static func isDuplicate(_ row: [String], check: DuplicateCheck?, parser: ImportValueParser) -> Bool {
        guard let check else { return false }
        let cell = row[check.column].trimmingCharacters(in: .whitespacesAndNewlines)
        return duplicateKey(cell, fieldType: check.fieldType, parser: parser).map(check.existingKeys.contains) ?? false
    }

    static func duplicateRowCount(_ table: ImportTable, hasHeaderRow: Bool, check: DuplicateCheck, parser: ImportValueParser) -> Int {
        dataRows(of: table, hasHeaderRow: hasHeaderRow).count { isDuplicate($0, check: check, parser: parser) }
    }

    /// Items are dated `start` plus a millisecond per row, so Date Added keeps the sheet's
    /// order, unless a column gives Date Added.
    static func build(
        _ table: ImportTable,
        plan: Plan,
        existing: [TargetField],
        parser: ImportValueParser,
        start: Date = .now
    ) -> Built {
        let headers = headers(of: table, hasHeaderRow: plan.hasHeaderRow)
        let rows = Array(dataRows(of: table, hasHeaderRow: plan.hasHeaderRow))

        var fieldDTOs: [FieldDefinitionDTO] = []
        var fieldIDForColumn: [Int: UUID] = [:]
        var takenNames = Set(existing.map { ImportFieldMatcher.normalised($0.name) })
        for (index, target) in plan.targets.enumerated() {
            switch target {
            case .field(let id):
                guard let field = existing.first(where: { $0.fieldID == id }) else { continue }
                fieldDTOs.append(FieldDefinitionDTO(fieldID: id, name: field.name, fieldType: field.fieldType,
                                                    priority: index, fieldOptions: nil, displayRole: nil))
                fieldIDForColumn[index] = id
            case .newField(let type):
                let name = ImportFieldMatcher.uniqueName(headers[index], among: takenNames)
                takenNames.insert(ImportFieldMatcher.normalised(name))
                let id = UUID()
                let values = rows.map { $0[index].trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                fieldDTOs.append(FieldDefinitionDTO(fieldID: id, name: name, fieldType: type, priority: index,
                                                    fieldOptions: options(for: type, values: values, parser: parser),
                                                    displayRole: nil))
                fieldIDForColumn[index] = id
            case .skip, .notes, .dateAdded:
                continue
            }
        }
        let fieldsByID = Dictionary(fieldDTOs.map { ($0.fieldID, $0) }, uniquingKeysWith: { first, _ in first })
        let existingByID = Dictionary(existing.map { ($0.fieldID, $0) }, uniquingKeysWith: { first, _ in first })

        var items: [CatalogueItemDTO] = []
        var skipped = 0
        var duplicates = 0
        for (rowIndex, row) in rows.enumerated() {
            if isDuplicate(row, check: plan.duplicateCheck, parser: parser) {
                duplicates += 1
                continue
            }
            var values: [FieldValueDTO] = []
            var notes: String?
            var dateAdded: Date?
            for (index, target) in plan.targets.enumerated() {
                let cell = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cell.isEmpty else { continue }
                switch target {
                case .skip:
                    continue
                case .notes:
                    notes = cell
                case .dateAdded:
                    dateAdded = parser.date(cell)
                case .field, .newField:
                    guard let id = fieldIDForColumn[index], let dto = fieldsByID[id] else { continue }
                    let field = existingByID[id] ?? TargetField(fieldID: id, name: dto.name, fieldType: dto.fieldType)
                    guard !(takesPlaceholders(field) && isPlaceholder(cell)), let value = read(cell, as: .field(id), field: field, parser: parser) else { continue }
                    values.append(value)
                }
            }
            guard !values.isEmpty || notes != nil else {
                skipped += 1
                continue
            }
            let created = dateAdded ?? start.addingTimeInterval(Double(rowIndex) / 1_000)
            items.append(CatalogueItemDTO(createdDate: created, modifiedDate: created, isWishlist: nil,
                                          notes: notes, fieldValues: values, photos: []))
        }

        let catalogue = CatalogueDTO(
            name: plan.catalogueName,
            iconName: "square.grid.2x2",
            iconImageData: nil,
            iconImageKind: nil,
            colorHex: plan.colorHex,
            createdDate: start,
            priority: 0,
            sortFieldKey: ItemSortField.dateAddedKey,
            sortDirection: ItemSortDirection.ascending.rawValue,
            showAllTab: false,
            fieldDefinitions: fieldDTOs,
            items: items
        )
        return Built(catalogue: catalogue, skippedRowCount: skipped, duplicateRowCount: duplicates)
    }

    // MARK: Values

    private static func takesPlaceholders(_ field: TargetField?) -> Bool {
        guard let field else { return false }
        return field.fieldType != .text && field.fieldType != .optionList
    }

    private static func fieldTarget(_ target: ColumnTarget, existing: [TargetField]) -> TargetField? {
        switch target {
        case .field(let id): existing.first { $0.fieldID == id }
        case .newField(let type): TargetField(fieldID: UUID(), name: "", fieldType: type)
        case .skip, .notes, .dateAdded: nil
        }
    }

    /// `nil` when the cell can't be read as the target. Notes and Skip take anything.
    private static func read(_ cell: String, as target: ColumnTarget, field: TargetField?, parser: ImportValueParser) -> FieldValueDTO? {
        switch target {
        case .skip, .notes:
            return FieldValueDTO(fieldDefinitionID: UUID(), fieldType: .text, textValue: cell, numberValue: nil, dateValue: nil, boolValue: nil)
        case .dateAdded:
            return parser.date(cell).map {
                FieldValueDTO(fieldDefinitionID: UUID(), fieldType: .date, textValue: nil, numberValue: nil, dateValue: $0, boolValue: nil)
            }
        case .field, .newField:
            guard let field else { return nil }
            var value = FieldValueDTO(fieldDefinitionID: field.fieldID, fieldType: field.fieldType,
                                      textValue: nil, numberValue: nil, dateValue: nil, boolValue: nil)
            switch field.fieldType {
            case .text:
                value.textValue = cell
            case .optionList:
                value.textValue = canonicalOption(cell, in: field.options) ?? cell
            case .number:
                guard let number = parser.number(cell) else { return nil }
                value.numberValue = number.value
            case .date:
                guard let date = parser.date(cell) else { return nil }
                value.dateValue = date
            case .boolean:
                guard let bool = parser.bool(cell, trueLabel: field.trueLabel, falseLabel: field.falseLabel) else { return nil }
                value.boolValue = bool
            }
            return value
        }
    }

    /// An existing option spelled differently (`owned` for `Owned`) is that option.
    private static func canonicalOption(_ cell: String, in options: [String]) -> String? {
        let key = ImportFieldMatcher.normalised(cell)
        return options.first { ImportFieldMatcher.normalised($0) == key }
    }

    /// A new option list lists its values in first-seen order; a new number field shows the
    /// most decimal places the column uses (up to four), as currency when any value had a
    /// currency symbol.
    private static func options(for type: FieldType, values: [String], parser: ImportValueParser) -> FieldOptions? {
        switch type {
        case .optionList:
            var seen = Set<String>()
            var options: [String] = []
            for value in values where seen.insert(ImportFieldMatcher.normalised(value)).inserted {
                options.append(value)
            }
            return .optionList(OptionListOptions(options: options))
        case .number:
            let numbers = values.filter { !isPlaceholder($0) }.compactMap(parser.number)
            let precision = min(numbers.map(\.fractionDigits).max() ?? 0, 4)
            let format: NumberFormat = numbers.contains(where: \.hadCurrencySymbol) ? .currency : .number
            return .number(NumberOptions(format: format, precision: precision))
        case .text, .date, .boolean:
            return nil
        }
    }
}
