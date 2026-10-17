//
//  ItemDerivedColumns.swift
//  catalogue-it
//

import Foundation

// MARK: - Item Derived Columns

/// The one place that recomputes what derives from an item's field values. Writes only what
/// differs, so recomputing on save, in a sweep or after a merge never turns an already-correct
/// item into an export, and the other device's rebuild comes back as a no-op. Never touches
/// `modifiedDate`, which records the user's last edit.
enum ItemDerivedColumns {

    /// - Parameters:
    ///   - fieldValues: One per definition.
    ///   - definitions: Sorted by priority.
    static func refresh(
        on item: CatalogueItem,
        fieldValues: [FieldValue],
        definitions: [FieldDefinition]
    ) {
        for value in fieldValues {
            let sortKey = SortKeyEncoder.sortKey(for: value)
            if value.sortKey != sortKey { value.sortKey = sortKey }
        }
        // Tiebreak keys depend on every field's sortKey, so they come second.
        for value in fieldValues {
            let tiebreakKey = SortKeyEncoder.tiebreakKey(
                for: value,
                allFieldValuesOnItem: fieldValues,
                fieldDefinitionsByPriority: definitions,
                itemCreatedDate: item.createdDate
            )
            if value.tiebreakKey != tiebreakKey { value.tiebreakKey = tiebreakKey }
        }

        let searchText = SearchTextBuilder.build(from: fieldValues)
        if item.searchText != searchText { item.searchText = searchText }

        ItemFacetBuilder.apply(to: item, fieldValues: fieldValues, definitions: definitions)
    }
}
