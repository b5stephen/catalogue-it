//
//  SearchTextBuilder.swift
//  catalogue-it
//

import Foundation

// MARK: - Search Text Builder

/// Builds the denormalised search blob stored in `CatalogueItem.searchText`, and normalises
/// the user's query to match it.
///
/// The blob is a lowercased, space-joined concatenation of every field value in a
/// **canonical, locale-independent form**. Storing it on the item row lets SwiftData push
/// text search to SQLite via a `CONTAINS` predicate — no item is loaded into Swift memory
/// until a match is confirmed.
///
/// Canonical rather than the display form because the blob syncs, and every device must
/// compute the *same* blob from the same values. `RemoteChangeObserver` rebuilds it after
/// a merge, and that rebuild is exported; if a phone set to en_NZ and a Mac set to en_US
/// produced different blobs ("1,979" vs "1.979", "NZ$" vs "$", "Yes" vs "Oui"), each
/// device's rebuild would be a change the other had to re-import and re-export, forever.
/// So:
/// - Text and option-list values are lowercased. Not locale-aware, matching `SortKeyEncoder`.
/// - Numbers are written without grouping, with "." as the decimal separator and no trailing
///   zeros ("1979", "12.5"). `normaliseQuery` folds the user's locale-formatted query onto
///   the same shape, so typing "1,979" still finds it.
/// - Dates are `yyyy-MM-dd` tokens. A stored date is an instant, and which calendar day it
///   falls on depends on the zone it is read in — 9am on 12 March in Auckland is still
///   11 March in GMT — so no single zone is right for everyone, and the local zone would
///   differ per device. Instead the GMT day of the instant, of 14 hours earlier and of
///   14 hours later are all indexed (deduplicated; zones span UTC−12 to UTC+14), so the day
///   the user sees is always among them, on every device. A date search can therefore also
///   match the neighbouring day. Dates are searchable by ISO date only — not by month name,
///   which has no locale-free spelling.
/// - Booleans are omitted. "yes" would match nearly every item in a catalogue with a flag
///   field, so the value it once contributed was noise.
/// - Values are ordered by field priority, then by content. The to-many relationship hands
///   them back in no particular order, and the same words in a different order would be a
///   different blob.
///
/// Changing any rule here changes what every existing row should hold: bump
/// `formatVersion` so `DerivedDataBackfill` rewrites the column once per device.
nonisolated enum SearchTextBuilder {

    /// Version of the encoding rules above. Stored in user defaults by `DerivedDataBackfill`,
    /// which rebuilds every item's `searchText` when the value it recorded is behind this one.
    static let formatVersion = 2

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Builds the canonical search blob from an array of `FieldValue`s.
    /// Call this after all field values for an item have been saved, then assign the
    /// result to `CatalogueItem.searchText`.
    static func build(from fieldValues: [FieldValue]) -> String {
        let blob = fieldValues
            .compactMap { value -> (priority: Int, text: String)? in
                guard let text = canonicalValue(value), !text.isEmpty else { return nil }
                return (value.fieldDefinition?.priority ?? Int.max, text)
            }
            .sorted { ($0.priority, $0.text) < ($1.priority, $1.text) }
            .map(\.text)
            .joined(separator: " ")
        // Unbounded by construction, and it shares a 1 MB CloudKit record with everything else
        // on the item. Recorded so the diagnostics screen can confirm or rule out record size
        // as a cause; the guard inside keeps this free below the threshold.
        SyncDiagnostics.noteFieldSize("CatalogueItem.searchText", blob.utf8.count)
        return blob
    }

    /// One field's contribution to the blob, or `nil` for a value that isn't indexed.
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

    /// The GMT days of the instant and of ±14h, in order, each once.
    static func dateTokens(_ date: Date) -> String {
        let days = [-14.0, 0, 14].map { isoDay.string(from: date.addingTimeInterval($0 * 3600)) }
        var seen: Set<String> = []
        return days.filter { seen.insert($0).inserted }.joined(separator: " ")
    }

    /// "1979" for a whole number, otherwise Swift's shortest round-trip description
    /// ("12.5", "0.1"). Both are locale-free and identical on every platform.
    static func canonicalNumber(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    // MARK: - Query

    /// The two strings a search compares against the blob: what the user typed, lowercased,
    /// and — when the whole query is a number written the way a person writes numbers —
    /// the same number folded onto the blob's shape (grouping removed, the locale's decimal
    /// separator swapped for ".", trailing zeros dropped, so a field shown as "1,979.00" is
    /// found by typing exactly that). A match on either counts. Matching the raw form as
    /// well means a query is never *only* reinterpreted because it looks numeric: "2,5" in
    /// a text field still matches "2,5". `canonical == raw` when there is nothing to fold.
    ///
    /// Grouping accepts the locale's separator plus the space family (U+0020, U+00A0,
    /// U+202F) and apostrophes, since keyboards type U+0020 where the locale formats U+202F.
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
