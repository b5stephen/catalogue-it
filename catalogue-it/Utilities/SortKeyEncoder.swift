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
enum SortKeyEncoder {

    /// Sentinel placed in `sortKey` when the field has no value. Sorts last in ascending order.
    static let missingValueSentinel = "\u{FFFF}"

    /// Offset added to all numbers before encoding, ensuring practical values are positive.
    private static let numberOffset: Double = 1e12

    private static let iso8601: ISO8601DateFormatter = {
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
        }
    }
}
