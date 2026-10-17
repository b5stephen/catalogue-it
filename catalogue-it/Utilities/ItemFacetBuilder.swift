//
//  ItemFacetBuilder.swift
//  catalogue-it
//

import Foundation

// MARK: - Item Facet Builder

/// Mirrors of status and flag values onto `CatalogueItem`, so filtering stays an indexed column
/// comparison: filtering through `FieldValue` would join past the
/// `[catalogue, deletedDate, statusValue, createdDate]` index the paginated fetch relies on.
/// `FieldValue` stays the source of truth; every write path maintains the mirror.
nonisolated enum ItemFacetBuilder {

    // MARK: - Encoding

    /// The `\u{1}` prefix can't collide with a typed option value.
    static let boolTrueToken = "\u{1}1"
    static let boolFalseToken = "\u{1}0"

    /// Delimited both sides, so `CONTAINS` can't match a partial UUID.
    static func flagToken(for fieldID: UUID) -> String {
        "|\(fieldID.uuidString)|"
    }

    // MARK: - Building

    /// - Parameters:
    ///   - definitions: Only those carrying a display role are consulted.
    static func facets(
        from fieldValues: [FieldValue],
        definitions: [FieldDefinition]
    ) -> (statusValue: String, flagKeys: String) {
        (
            statusValue: statusValue(from: fieldValues, definitions: definitions),
            flagKeys: flagKeys(from: fieldValues, definitions: definitions)
        )
    }

    /// Assigns only what differs, so an already-correct item stays clean and exports nothing.
    /// Every write path should use this rather than setting the columns.
    static func apply(
        to item: CatalogueItem,
        fieldValues: [FieldValue],
        definitions: [FieldDefinition]
    ) {
        let facets = facets(from: fieldValues, definitions: definitions)
        if item.statusValue != facets.statusValue { item.statusValue = facets.statusValue }
        if item.flagKeys != facets.flagKeys { item.flagKeys = facets.flagKeys }
    }

    // MARK: - Components

    /// `""` without a valid status field or a value for it.
    static func statusValue(from fieldValues: [FieldValue], definitions: [FieldDefinition]) -> String {
        guard let statusField = definitions.first(where: { $0.isStatusField }) else { return "" }
        guard let value = SortKeyEncoder.preferredValue(for: statusField, among: fieldValues)
        else { return "" }

        switch statusField.fieldType {
        case .optionList:
            // A removed option no longer names a tab, so it counts as unset.
            guard let text = value.textValue, !text.isEmpty,
                  statusField.optionListOptions?.options.contains(text) == true
            else { return "" }
            return text
        case .boolean:
            // Exhaustive: an absent value is false, so the item lands in a tab rather than none.
            return value.boolValue == true ? boolTrueToken : boolFalseToken
        case .text, .number, .date:
            return ""
        }
    }

    static func flagKeys(from fieldValues: [FieldValue], definitions: [FieldDefinition]) -> String {
        let flagFields = definitions.filter { $0.isFlagField }
        guard !flagFields.isEmpty else { return "" }

        return flagFields
            .filter { field in
                SortKeyEncoder.preferredValue(for: field, among: fieldValues)?.boolValue == true
            }
            .map { flagToken(for: $0.fieldID) }
            .joined()
    }
}
