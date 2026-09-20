//
//  ItemDerivedColumns.swift
//  catalogue-it
//

import Foundation

// MARK: - Item Derived Columns

/// The one place that recomputes everything derived from an item's field values: sort and
/// tiebreak keys on each `FieldValue`, and the search blob and facet mirrors on the item.
///
/// Every column is assigned only when it differs from what is stored. That is what keeps
/// the derived state safe to recompute freely — on save, in a maintenance sweep, and after
/// a CloudKit merge — without every pass becoming an export: an item whose derived columns
/// are already right stays clean, and a rebuild on the other device that arrives back here
/// computes the same values and writes nothing. The encoders are deterministic across
/// devices for the same reason (see `SearchTextBuilder`).
///
/// `modifiedDate` is deliberately never touched here. It records the user's last edit, and
/// is the key the thumbnail views reload on.
enum ItemDerivedColumns {

    /// Recomputes and, where changed, writes the derived columns for one item.
    /// - Parameters:
    ///   - fieldValues: Every `FieldValue` belonging to the item, one per definition.
    ///   - definitions: The catalogue's definitions, sorted by priority.
    static func refresh(
        on item: CatalogueItem,
        fieldValues: [FieldValue],
        definitions: [FieldDefinition]
    ) {
        for value in fieldValues {
            let sortKey = SortKeyEncoder.sortKey(for: value)
            if value.sortKey != sortKey { value.sortKey = sortKey }
        }
        // Tiebreak keys depend on every field's sortKey, so they follow in a second pass.
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
