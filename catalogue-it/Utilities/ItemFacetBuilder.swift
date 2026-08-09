//
//  ItemFacetBuilder.swift
//  catalogue-it
//

import Foundation

// MARK: - Item Facet Builder

/// Builds the denormalised status/flag columns stored on `CatalogueItem`.
///
/// `FieldValue` remains the source of truth for status and flag data — these columns
/// are a mirror, maintained by every write path (item save, import, seed, and the
/// backfill that runs when a field's configuration changes).
///
/// The mirror exists for query performance. Filtering by a child `FieldValue` would
/// force a join that defeats the compound `#Index<CatalogueItem>` covering
/// `[catalogue, deletedDate, statusValue, createdDate]`, which is the index the
/// paginated item fetch depends on. Mirroring keeps status filtering a plain indexed
/// column comparison, exactly as the old `isWishlist` boolean was.
///
/// Same pattern as `SearchTextBuilder` and `SortKeyEncoder`.
// `nonisolated` because the project defaults to main-actor isolation, and these helpers
// are called from nonisolated SwiftData model extensions as well as from the main actor.
nonisolated enum ItemFacetBuilder {

    // MARK: - Encoding

    /// Sentinel written to `statusValue` for the `true` side of a `.boolean` status field.
    /// The `\u{1}` prefix guarantees no collision with a user-typed option-list value.
    static let boolTrueToken = "\u{1}1"
    /// Sentinel written to `statusValue` for the `false` side of a `.boolean` status field.
    static let boolFalseToken = "\u{1}0"

    /// The token a flag field contributes to `flagKeys` when set on an item.
    /// Wrapped in delimiters on both sides so a `CONTAINS` predicate can never match
    /// a partial UUID or run past a boundary.
    static func flagToken(for fieldID: UUID) -> String {
        "|\(fieldID.uuidString)|"
    }

    // MARK: - Building

    /// Computes both denormalised columns for an item from its field values.
    ///
    /// - Parameters:
    ///   - fieldValues: Every `FieldValue` belonging to the item.
    ///   - definitions: The catalogue's field definitions. Only those carrying a
    ///     display role are consulted.
    static func facets(
        from fieldValues: [FieldValue],
        definitions: [FieldDefinition]
    ) -> (statusValue: String, flagKeys: String) {
        (
            statusValue: statusValue(from: fieldValues, definitions: definitions),
            flagKeys: flagKeys(from: fieldValues, definitions: definitions)
        )
    }

    /// Computes and assigns both columns on the item in one step.
    /// Every write path should call this rather than setting the columns directly.
    static func apply(
        to item: CatalogueItem,
        fieldValues: [FieldValue],
        definitions: [FieldDefinition]
    ) {
        let facets = facets(from: fieldValues, definitions: definitions)
        item.statusValue = facets.statusValue
        item.flagKeys = facets.flagKeys
    }

    // MARK: - Components

    /// The status token for an item, or `""` when the catalogue has no valid status
    /// field or the item has no value for it.
    static func statusValue(from fieldValues: [FieldValue], definitions: [FieldDefinition]) -> String {
        guard let statusField = definitions.first(where: { $0.isStatusField }) else { return "" }
        guard let value = fieldValues.first(where: { $0.fieldDefinition?.fieldID == statusField.fieldID })
        else { return "" }

        switch statusField.fieldType {
        case .optionList:
            // An option removed from the field's option set no longer names a tab,
            // so it is treated as unset rather than filtered into a tab that isn't shown.
            guard let text = value.textValue, !text.isEmpty,
                  statusField.optionListOptions?.options.contains(text) == true
            else { return "" }
            return text
        case .boolean:
            // A boolean status is exhaustive — an absent value reads as false, so the
            // item lands in the `falseLabel` tab rather than vanishing from every tab.
            return value.boolValue == true ? boolTrueToken : boolFalseToken
        case .text, .number, .date:
            return ""
        }
    }

    /// The concatenated flag tokens for an item, or `""` when no flags are set.
    static func flagKeys(from fieldValues: [FieldValue], definitions: [FieldDefinition]) -> String {
        let flagFields = definitions.filter { $0.isFlagField }
        guard !flagFields.isEmpty else { return "" }

        return flagFields
            .filter { field in
                fieldValues.first { $0.fieldDefinition?.fieldID == field.fieldID }?.boolValue == true
            }
            .map { flagToken(for: $0.fieldID) }
            .joined()
    }
}
