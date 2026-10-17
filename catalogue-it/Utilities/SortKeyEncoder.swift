//
//  SortKeyEncoder.swift
//  catalogue-it
//

import Foundation

// MARK: - Sort Key Encoder

/// For `FieldValue.sortKey`, so custom-field sorting happens in the store.
/// - Text: lowercased, byte order (not locale-aware).
/// - Number: offset by `1e12` and formatted `%021.6f`, so practical values are positive and
///   zero-padded strings sort numerically.
/// - Date: ISO 8601. Boolean: "0"/"1". Missing: `missingValueSentinel`, sorting last.
nonisolated enum SortKeyEncoder {

    static let missingValueSentinel = "\u{FFFF}"

    private static let numberOffset: Double = 1e12

    // Thread-safe per its documentation; only the type lacks the Sendable annotation.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f
    }()

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
            // Width 21 = 14 integer digits + "." + 6 decimals.
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

    /// Sorts below any content and below `missingValueSentinel`. Not NUL: SwiftData's string
    /// storage truncates at the first NUL byte, which dropped every segment after the first.
    static let tiebreakSeparator = "\u{0001}"

    /// Every other field's sortKey in priority order, then the item's `createdDate`. Always
    /// compared ascending, whatever the primary direction.
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
        // Quadratic in field count and unbounded in text length, against a 1 MB record limit.
        // Recorded for the same reason as searchText.
        SyncDiagnostics.noteFieldSize("FieldValue.tiebreakKey", key.utf8.count)
        return key
    }
}

// MARK: - Duplicate Values

nonisolated extension SortKeyEncoder {
    /// The one value to read when an item holds several for a definition (two devices each
    /// created the row). Smallest `sortKey` is the same on every device and prefers a populated
    /// value; relationship order, which `first(where:)` uses, differs per device.
    static func preferredValue(for definition: FieldDefinition, among fieldValues: [FieldValue]) -> FieldValue? {
        preferredValue(forFieldID: definition.fieldID, among: fieldValues)
    }

    static func preferredValue(forFieldID fieldID: UUID, among fieldValues: [FieldValue]) -> FieldValue? {
        fieldValues
            .filter { $0.fieldDefinition?.fieldID == fieldID }
            .min { sortKey(for: $0) < sortKey(for: $1) }
    }
}
