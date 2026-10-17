//
//  SearchTextBuilder.swift
//  catalogue-it
//

import Foundation

// MARK: - Search Text Builder

/// The blob in `CatalogueItem.searchText`, matched with a `CONTAINS` predicate in the store.
///
/// Canonical and locale-free because it syncs: devices in different locales must compute the
/// same blob, or each one's rebuild is a change the other re-imports and re-exports forever.
/// - Text and options are lowercased, not locale-aware, matching `SortKeyEncoder`.
/// - Numbers are ungrouped with "." and no trailing zeros ("1979", "12.5"); `queryVariants`
///   folds a locale-formatted query onto that shape.
/// - Dates are `yyyy-MM-dd` for the GMT days of the instant and of ±14h, since the day a user
///   sees depends on their zone (UTC−12 to +14). A date search can also match a neighbouring
///   day. No month names, which have no locale-free spelling.
/// - Booleans are omitted: "yes" would match nearly every item with a flag.
/// - Values are ordered by field priority then content, since relationship order varies.
///
/// Changing a rule: bump `formatVersion` so `DerivedDataBackfill` rewrites the column once
/// per device.
nonisolated enum SearchTextBuilder {

    /// `DerivedDataBackfill` rebuilds every item's `searchText` when its recorded value is behind.
    static let formatVersion = 2

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func build(from fieldValues: [FieldValue]) -> String {
        let blob = fieldValues
            .compactMap { value -> (priority: Int, text: String)? in
                guard let text = canonicalValue(value), !text.isEmpty else { return nil }
                return (value.fieldDefinition?.priority ?? Int.max, text)
            }
            .sorted { ($0.priority, $0.text) < ($1.priority, $1.text) }
            .map(\.text)
            .joined(separator: " ")
        // Unbounded, and it shares a 1 MB record with the rest of the item: recorded so diagnostics
        // can confirm or rule out record size. Free below the threshold.
        SyncDiagnostics.noteFieldSize("CatalogueItem.searchText", blob.utf8.count)
        return blob
    }

    /// `nil` for a value that isn't indexed.
    private static func canonicalValue(_ value: FieldValue) -> String? {
        switch value.fieldType {
        case .text, .optionList:
            return value.textValue?.lowercased()
        case .number:
            return value.numberValue.map(canonicalNumber)
        case .date:
            return value.dateValue.map(dateTokens)
        case .boolean:
            return nil
        }
    }

    static func dateTokens(_ date: Date) -> String {
        let days = [-14.0, 0, 14].map { isoDay.string(from: date.addingTimeInterval($0 * 3600)) }
        var seen: Set<String> = []
        return days.filter { seen.insert($0).inserted }.joined(separator: " ")
    }

    /// Locale-free and identical on every platform.
    static func canonicalNumber(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    // MARK: - Query

    /// What the user typed, lowercased, and — when the whole query is a number as people write
    /// them — that number folded onto the blob's shape, so "1,979.00" finds it. Either matching
    /// counts, so a numeric-looking query is never *only* reinterpreted. `canonical == raw` when
    /// there's nothing to fold. Grouping also accepts the space family and apostrophes, since
    /// keyboards type U+0020 where the locale formats U+202F.
    static func queryVariants(_ query: String, locale: Locale = .current) -> (raw: String, canonical: String) {
        let raw = query.lowercased()
        let decimal = locale.decimalSeparator ?? "."
        var grouping = Set([locale.groupingSeparator ?? ",", " ", "\u{00A0}", "\u{202F}", "'", "\u{2019}"])
        grouping.remove(decimal)

        var numeric = CharacterSet.decimalDigits
        numeric.insert(charactersIn: decimal + grouping.joined())
        guard !raw.isEmpty,
              raw.unicodeScalars.allSatisfy(numeric.contains),
              raw.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains)
        else { return (raw, raw) }

        var canonical = raw
        for separator in grouping {
            canonical = canonical.replacingOccurrences(of: separator, with: "")
        }
        if decimal != "." {
            canonical = canonical.replacingOccurrences(of: decimal, with: ".")
        }
        if canonical.contains(".") {
            while canonical.hasSuffix("0") { canonical.removeLast() }
            if canonical.hasSuffix(".") { canonical.removeLast() }
        }
        return (raw, canonical.isEmpty ? raw : canonical)
    }
}
