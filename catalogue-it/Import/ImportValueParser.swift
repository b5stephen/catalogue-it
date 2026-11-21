//
//  ImportValueParser.swift
//  catalogue-it
//

import Foundation

// MARK: - Date Order

nonisolated enum ImportDateOrder: String, CaseIterable, Identifiable, Sendable {
    case dayMonthYear
    case monthDayYear

    var id: Self { self }

    /// The order the locale writes a numeric date in.
    static func preferred(for locale: Locale) -> ImportDateOrder {
        let pattern = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: locale) ?? ""
        guard let day = pattern.firstIndex(of: "d"), let month = pattern.firstIndex(of: "M") else { return .dayMonthYear }
        return day < month ? .dayMonthYear : .monthDayYear
    }
}

// MARK: - Import Value Parser

/// Reads spreadsheet cells as field values. Holds formatters, so make one per import and keep it
/// on one thread.
nonisolated final class ImportValueParser {

    struct ParsedNumber: Equatable {
        let value: Double
        let fractionDigits: Int
        let hadCurrencySymbol: Bool
    }

    let locale: Locale
    let calendar: Calendar
    var dateOrder: ImportDateOrder

    init(locale: Locale = .current, timeZone: TimeZone = .current, dateOrder: ImportDateOrder? = nil) {
        self.locale = locale
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.dateOrder = dateOrder ?? .preferred(for: locale)
    }

    // MARK: Numbers

    /// Plain (`1234.5`) first, then grouped forms either way round (`1,234.50`, `1.234,50`,
    /// `1 234,5`, `1'234.50`). Currency symbols and a leading `+` are dropped; `(12)` is
    /// negative. A lone separator before exactly three digits (`1,234`) is grouping unless the
    /// locale uses it as its decimal mark.
    func number(_ text: String) -> ParsedNumber? {
        var hadCurrency = false
        var negative = false
        var body = ""
        for scalar in text.unicodeScalars {
            if scalar.properties.generalCategory == .currencySymbol {
                hadCurrency = true
            } else if !scalar.properties.isWhitespace && scalar != "'" && scalar != "’" {
                body.unicodeScalars.append(scalar)
            }
        }
        if body.hasPrefix("("), body.hasSuffix(")") {
            negative = true
            body = String(body.dropFirst().dropLast())
        }
        if body.hasPrefix("-") || body.hasPrefix("−") {
            negative.toggle()
            body.removeFirst()
        } else if body.hasPrefix("+") {
            body.removeFirst()
        }
        guard !body.isEmpty, body.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }),
              body.first?.isNumber == true, body.last?.isNumber == true else { return nil }

        let dots = body.count { $0 == "." }
        let commas = body.count { $0 == "," }
        let decimal: Character?
        switch (dots, commas) {
        case (0, 0):
            decimal = nil
        case (_, 0), (0, _):
            let separator: Character = dots > 0 ? "." : ","
            let count = max(dots, commas)
            let after = body.split(separator: separator).last?.count ?? 0
            if count > 1 {
                decimal = nil
            } else if after == 3 {
                decimal = locale.decimalSeparator == String(separator) ? separator : nil
            } else {
                decimal = separator
            }
        default:
            // Both present: the last one is the decimal mark, and it may appear only once.
            decimal = body.lastIndex(of: ".")! > body.lastIndex(of: ",")! ? "." : ","
            if body.count(where: { $0 == decimal }) > 1 { return nil }
        }

        let parts = decimal.map { body.split(separator: $0, omittingEmptySubsequences: false) } ?? [Substring(body)]
        let integerPart = parts[0]
        let fraction = parts.count > 1 ? parts[1] : ""
        let groups = integerPart.split(whereSeparator: { $0 == "." || $0 == "," }).map(String.init)
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        guard fraction.allSatisfy(\.isNumber),
              let value = Double(groups.joined() + (fraction.isEmpty ? "" : "." + fraction)) else { return nil }
        return ParsedNumber(value: negative ? -value : value, fractionDigits: fraction.count, hadCurrencySymbol: hadCurrency)
    }

    // MARK: Dates

    private lazy var isoDateTime: ISO8601DateFormatter = ISO8601DateFormatter()
    private lazy var isoDateTimeFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private lazy var textualFormatters: [DateFormatter] = {
        let localised: [DateFormatter] = [DateFormatter.Style.medium, .long, .full].map { style in
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = style
            formatter.timeStyle = .none
            return formatter
        }
        let english = ["d MMM yyyy", "d MMMM yyyy", "MMM d, yyyy", "MMMM d, yyyy", "d-MMM-yyyy", "d-MMM-yy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            return formatter
        }
        return localised + english
    }()

    /// A full ISO timestamp keeps its instant. Anything naming only a day is noon that day here,
    /// so it reads as the same day in nearby time zones: `2026-03-01`, `1/3/2026` (in
    /// `dateOrder`), `1 Mar 2026`, `March 1, 2026`.
    func date(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("T"), let instant = isoDateTime.date(from: trimmed) ?? isoDateTimeFractional.date(from: trimmed) {
            return instant
        }
        if let parts = numericDateParts(trimmed) {
            return day(year: parts.year, month: parts.month, day: parts.day)
        }
        guard trimmed.contains(where: \.isLetter) else { return nil }
        for formatter in textualFormatters {
            if let parsed = formatter.date(from: trimmed) {
                let parts = calendar.dateComponents([.year, .month, .day], from: parsed)
                return day(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
            }
        }
        return nil
    }

    /// The raw first and second numbers of a numeric date, before `dateOrder` assigns them, for
    /// working out which order a column uses.
    func numericDateLeadingParts(_ text: String) -> (first: Int, second: Int)? {
        let parts = numericParts(text.trimmingCharacters(in: .whitespaces))
        guard let parts, parts.count == 3, parts[0].count <= 2 else { return nil }
        guard let first = Int(parts[0]), let second = Int(parts[1]) else { return nil }
        return (first, second)
    }

    private func numericParts(_ text: String) -> [Substring]? {
        let parts = text.split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." })
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return parts
    }

    private func numericDateParts(_ text: String) -> (year: Int, month: Int, day: Int)? {
        guard let parts = numericParts(text), let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else {
            return nil
        }
        if parts[0].count == 4 { return (a, b, c) }
        guard parts[2].count == 4 || parts[2].count == 2, parts[0].count <= 2, parts[1].count <= 2 else { return nil }
        let year = parts[2].count == 4 ? c : expandTwoDigitYear(c)
        switch dateOrder {
        case .dayMonthYear: return (year, b, a)
        case .monthDayYear: return (year, a, b)
        }
    }

    /// Up to ten years ahead is this century; the rest the last.
    private func expandTwoDigitYear(_ year: Int) -> Int {
        let current = calendar.component(.year, from: .now)
        let century = current / 100 * 100
        return century + year > current + 10 ? century - 100 + year : century + year
    }

    private func day(year: Int, month: Int, day: Int) -> Date? {
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard (1...12).contains(month), (1...31).contains(day), year > 0,
              let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    // MARK: Yes/No

    private static let trueWords: Set<String> = ["yes", "y", "true", "t", "x", "✓", "✔", "✔︎", "on", "1"]
    private static let falseWords: Set<String> = ["no", "n", "false", "f", "✗", "✘", "off", "0", "-"]

    /// Also accepts the field's own labels and the app's localised Yes and No.
    func bool(_ text: String, trueLabel: String? = nil, falseLabel: String? = nil) -> Bool? {
        let key = ImportFieldMatcher.normalised(text)
        guard !key.isEmpty else { return nil }
        if Self.trueWords.contains(key) || key == ImportFieldMatcher.normalised(String(localized: "Yes"))
            || trueLabel.map(ImportFieldMatcher.normalised) == key { return true }
        if Self.falseWords.contains(key) || key == ImportFieldMatcher.normalised(String(localized: "No"))
            || falseLabel.map(ImportFieldMatcher.normalised) == key { return false }
        return nil
    }

    /// Stricter than `bool`, for guessing a column's type: `1` and `0` alone read as numbers.
    func looksBoolean(_ text: String) -> Bool {
        let key = ImportFieldMatcher.normalised(text)
        return key != "1" && key != "0" && bool(text) != nil
    }
}
