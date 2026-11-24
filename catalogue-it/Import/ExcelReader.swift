//
//  ExcelReader.swift
//  catalogue-it
//

import Foundation

// MARK: - Excel Reader

/// Reads the visible worksheets of an Excel workbook — .xlsx through `XLSXReader`, .xls through
/// `XLSReader` — as tables of text, written so `ImportValueParser` reads them back as the values
/// Excel shows: dates as `yyyy-MM-dd`, percentages ×100, a currency format's symbol kept,
/// numbers to 15 significant digits.
nonisolated enum ExcelReader {

    struct Sheet: Equatable, Sendable {
        let name: String
        let table: ImportTable
    }

    enum ReadError: LocalizedError, Equatable {
        case passwordProtected
        case legacyFormat
        case numbersFile
        case notAWorkbook

        var errorDescription: String? {
            switch self {
            case .passwordProtected:
                String(localized: "This workbook is password-protected. Remove the password in Excel and save it, then import it again.")
            case .legacyFormat:
                String(localized: "This Excel file is older than Excel 97. Save it as an Excel workbook (.xlsx) or CSV, then import that.")
            case .numbersFile:
                String(localized: "Catalogue-It can’t read Numbers files. Export it from Numbers as Excel or CSV, then import that.")
            case .notAWorkbook:
                String(localized: "This file isn’t an Excel workbook that Catalogue-It can read.")
            }
        }
    }

    /// A zip (.xlsx, or a Numbers file), or an OLE compound file (.xls, or an encrypted .xlsx).
    static func isWorkbook(_ data: Data) -> Bool {
        ZipArchive.isZip(data) || CompoundFile.isCompoundFile(data)
    }

    /// Visible worksheets with at least one value, in workbook order.
    static func read(_ data: Data) throws -> [Sheet] {
        let sheets: [Sheet]
        do {
            sheets = CompoundFile.isCompoundFile(data) ? try XLSReader.sheets(data) : try XLSXReader.sheets(data)
        } catch let error as ReadError {
            throw error
        } catch {
            throw ReadError.notAWorkbook
        }
        guard !sheets.isEmpty else { throw DelimitedTextParser.ParseError.empty }
        return sheets
    }

    /// Cells by column, in row order. Rows with no value are left out, and every row is made
    /// as wide as the widest.
    static func table(from rows: [[Int: String]]) -> ImportTable? {
        let width = (rows.compactMap { $0.keys.max() }.max() ?? -1) + 1
        let filled = rows.filter { $0.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard width > 0, !filled.isEmpty else { return nil }
        return ImportTable(rows: filled.map { cells in (0..<width).map { cells[$0] ?? "" } })
    }

    // MARK: Cell Formatter

    /// Turns a cell's stored value into the text Excel would show, as far as an import needs.
    struct CellFormatter {

        enum Style: Equatable {
            case number(fractionDigits: Int, currencySymbol: String?, isPercent: Bool)
            case date
            case time(showsSeconds: Bool, isElapsed: Bool)

            static let general = Style.number(fractionDigits: 0, currencySymbol: nil, isPercent: false)

            /// Reads the first (positive) section of a number format code.
            init(code: String) {
                var letters = ""
                var currency: String?
                var characters = code.makeIterator()
                var inQuotes = false
                func noteCurrency(_ character: Character) {
                    if currency == nil, character.unicodeScalars.contains(where: { $0.properties.generalCategory == .currencySymbol }) {
                        currency = String(character)
                    }
                }
                scan: while let character = characters.next() {
                    if inQuotes {
                        if character == "\"" { inQuotes = false } else { noteCurrency(character) }
                        continue
                    }
                    switch character {
                    case "\"":
                        inQuotes = true
                    case ";":
                        break scan
                    case "\\":
                        if let next = characters.next() { noteCurrency(next) }
                    case "_", "*":
                        _ = characters.next()
                    case "[":
                        var bracket = ""
                        while let next = characters.next(), next != "]" { bracket.append(next) }
                        if bracket.hasPrefix("$") {
                            // [$€-407]: a symbol, then a locale; [$-409] is a locale alone.
                            let symbol = bracket.dropFirst().prefix { $0 != "-" }
                            if !symbol.isEmpty, currency == nil { currency = String(symbol) }
                        } else if let first = bracket.lowercased().first, "hms".contains(first) {
                            letters += "[" + bracket.lowercased()
                        }
                    default:
                        noteCurrency(character)
                        letters.append(contentsOf: character.lowercased())
                    }
                }

                if letters.contains("d") || letters.contains("y") {
                    self = .date
                } else if letters.contains("h") || letters.contains("s") {
                    self = .time(showsSeconds: letters.contains("s"), isElapsed: letters.contains("["))
                } else {
                    let fraction = letters.split(separator: ".", maxSplits: 1).dropFirst().first?.prefix { $0 == "0" }.count ?? 0
                    self = .number(fractionDigits: fraction, currencySymbol: currency, isPercent: letters.contains("%"))
                }
            }
        }

        let styles: [Style]
        let uses1904Dates: Bool

        func text(for value: Double, style index: Int?) -> String {
            let style = index.flatMap { styles.indices.contains($0) ? styles[$0] : nil } ?? .general
            switch style {
            case .number(let fractionDigits, let currencySymbol, let isPercent):
                return (currencySymbol ?? "") + Self.plain(isPercent ? value * 100 : value, fractionDigits: fractionDigits)
            case .date:
                return day(serial: value) ?? ""
            case .time(let showsSeconds, let isElapsed):
                let seconds = Int((value * 86_400).rounded())
                let hours = isElapsed ? seconds / 3_600 : seconds / 3_600 % 24
                let minutes = seconds / 60 % 60
                return showsSeconds
                    ? String(format: "%02d:%02d:%02d", hours, minutes, seconds % 60)
                    : String(format: "%02d:%02d", hours, minutes)
            }
        }

        /// No grouping or exponent, so `ImportValueParser` reads it in any locale; at least
        /// `fractionDigits` decimals, so the planner picks up the column's precision.
        static func plain(_ value: Double, fractionDigits: Int) -> String {
            let rounded = String(format: "%.15g", value)
            var text = Decimal(string: rounded, locale: Locale(identifier: "en_US_POSIX"))?.description ?? rounded
            let existing = text.split(separator: ".", maxSplits: 1).dropFirst().first?.count ?? 0
            if existing < fractionDigits {
                if existing == 0 { text += "." }
                text += String(repeating: "0", count: fractionDigits - existing)
            }
            return text
        }

        private static let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }()

        /// The day only: the parser reads a bare day as noon local, which keeps it the same
        /// day nearby. Serial 0 is Excel's empty date.
        func day(serial: Double) -> String? {
            let days = Int(serial.rounded(.down))
            guard days >= 1 else { return nil }
            // The 1900 system counts a 29 February 1900 that never was, so serials before
            // 1 March 1900 are one day further from the base.
            let base = uses1904Dates
                ? DateComponents(year: 1904, month: 1, day: 1)
                : DateComponents(year: 1899, month: 12, day: days < 61 ? 31 : 30)
            guard let start = Self.calendar.date(from: base),
                  let date = Self.calendar.date(byAdding: .day, value: days, to: start) else { return nil }
            let parts = Self.calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
    }

    /// Built-in number formats that matter here. 27–36 and 50–58 are East Asian dates.
    static func builtInFormatCode(_ id: Int) -> String {
        switch id {
        case 1: "0"
        case 2: "0.00"
        case 3: "#,##0"
        case 4: "#,##0.00"
        case 9: "0%"
        case 10: "0.00%"
        case 14: "mm-dd-yy"
        case 15: "d-mmm-yy"
        case 16: "d-mmm"
        case 17: "mmm-yy"
        case 18: "h:mm AM/PM"
        case 19: "h:mm:ss AM/PM"
        case 20: "h:mm"
        case 21: "h:mm:ss"
        case 22: "m/d/yy h:mm"
        case 27...36, 50...58: "yyyy-mm-dd"
        case 45: "mm:ss"
        case 46: "[h]:mm:ss"
        case 47: "mm:ss.0"
        default: "General"
        }
    }
}
