//
//  SortKeyEncoder.swift
//  catalogue-it
//

import Foundation

// MARK: - Sort Key Encoder

/// Converts a FieldValue's typed value into a lexicographically sortable string.
///
/// The encoded string is stored in `FieldValue.sortKey` and indexed for DB-level sorting.
/// This lets SwiftData push custom-field sort order to SQLite rather than sorting in-memory.
///
/// ## Encoding strategy
/// - **Text**: `lowercased()` — case-insensitive byte-order sort (not locale-aware).
/// - **Number**: offset by `1e12` then formatted to `%021.6f` — makes all practical values
///   positive so zero-padded strings sort correctly (e.g. `-5 → "00999999999995.000000"`).
/// - **Date**: ISO 8601 (`YYYY-MM-DDTHH:MM:SS`) — naturally sortable as-is.
/// - **Boolean**: `"0"` (false) or `"1"` (true).
/// - **Nil / missing**: `missingValueSentinel` (`"\u{FFFF}"`) — sorts after all real values.
nonisolated enum SortKeyEncoder {

    /// Sentinel placed in `sortKey` when the field has no value. Sorts last in ascending order.
    static let missingValueSentinel = "\u{FFFF}"

    /// Offset added to all numbers before encoding, ensuring practical values are positive.
    private static let numberOffset: Double = 1e12

    // Thread-safe per its documentation; only its type lacks the Sendable annotation.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f
    }()

    /// Returns the sortable string representation for the given field value.
    static func sortKey(for fieldValue: FieldValue) -> String {
        switch fieldValue.fieldType {
        case .text:
            guard let text = fieldValue.textValue, !text.isEmpty else {
                return missingValueSentinel
            }
            return text.lowercased()

        case .number:
            guard let number = fieldValue.numberValue else {
                return missingValueSentinel
            }
            // Offset makes negatives positive; zero-pad to fixed width for string sort.
            // Width 21 = 14 integer digits + "." + 6 decimal digits.
            return String(format: "%021.6f", number + numberOffset)

        case .date:
            guard let date = fieldValue.dateValue else {
                return missingValueSentinel
            }
            return iso8601.string(from: date)

        case .boolean:
            guard let bool = fieldValue.boolValue else {
                return missingValueSentinel
            }
            return bool ? "1" : "0"

        case .optionList:
            guard let text = fieldValue.textValue, !text.isEmpty else {
                return missingValueSentinel
            }
            return text.lowercased()
        }
    }
}

// MARK: - Tiebreak Key

nonisolated extension SortKeyEncoder {

    /// Separator between tiebreak segments in `FieldValue.tiebreakKey`. Sorts below any real
    /// content character and below `missingValueSentinel` ("\u{FFFF}"), so it never disturbs
    /// ordering within a segment. Deliberately NOT "\u{0000}" (NUL) — SwiftData's persisted
    /// String storage truncates at the first NUL byte (confirmed: a saved-and-refetched
    /// FieldValue.sortKey containing "\u{0000}" comes back truncated to the substring before
    /// it), which silently dropped every tiebreak segment after the first. "\u{0001}" (SOH)
    /// is not a string terminator anywhere in the storage pipeline and survives round-trips.
    static let tiebreakSeparator = "\u{0001}"

    /// Builds `FieldValue.tiebreakKey`: every other field's sortKey (in `FieldDefinition.priority`
    /// order, excluding `fieldValue`'s own field), followed by the item's `createdDate` (ISO 8601),
    /// joined by `tiebreakSeparator`. Always compared ascending — this is the tiebreak order
    /// `CatalogueItemSort` specifies regardless of the primary field's sort direction.
    static func tiebreakKey(
        for fieldValue: FieldValue,
        allFieldValuesOnItem: [FieldValue],
        fieldDefinitionsByPriority: [FieldDefinition],
        itemCreatedDate: Date
    ) -> String {
        let ownFieldID = fieldValue.fieldDefinition?.fieldID
        var parts: [String] = []
        for def in fieldDefinitionsByPriority where def.fieldID != ownFieldID {
            parts.append(preferredValue(for: def, among: allFieldValuesOnItem).map(sortKey(for:)) ?? missingValueSentinel)
        }
        parts.append(iso8601.string(from: itemCreatedDate))
        let key = parts.joined(separator: tiebreakSeparator)
        // Every *other* field's sortKey, stored on every FieldValue — quadratic in field count
        // and unbounded in text length, against a 1 MB per-record CloudKit limit. Recorded for
        // the same reason as searchText; threshold-gated, so the common path costs a compare.
        SyncDiagnostics.noteFieldSize("FieldValue.tiebreakKey", key.utf8.count)
        return key
    }
}

// MARK: - Duplicate Values

nonisolated extension SortKeyEncoder {
    /// The one `FieldValue` to read for `definition` when an item holds several — a merge
    /// artefact when two devices each create the row for a field the item lacked.
    ///
    /// Chosen by smallest `sortKey`, which is deterministic across devices (the key is a pure
    /// function of the value) and prefers a populated value, since every real key sorts below
    /// `missingValueSentinel`. Relationship order, which `first(where:)` would use, differs per
    /// device and would make every derived column that reads through here differ too.
    static func preferredValue(for definition: FieldDefinition, among fieldValues: [FieldValue]) -> FieldValue? {
        preferredValue(forFieldID: definition.fieldID, among: fieldValues)
    }

    static func preferredValue(forFieldID fieldID: UUID, among fieldValues: [FieldValue]) -> FieldValue? {
        fieldValues
            .filter { $0.fieldDefinition?.fieldID == fieldID }
            .min { sortKey(for: $0) < sortKey(for: $1) }
    }
}
