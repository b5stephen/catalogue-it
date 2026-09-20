//
//  CatalogueSortKeyMaintenance.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Catalogue Sort Key Maintenance

/// Recomputes every derived column across a whole catalogue — `FieldValue.sortKey` and
/// `.tiebreakKey`, `CatalogueItem.searchText` and the facet mirrors — through
/// `ItemDerivedColumns`, which writes only what actually differs.
///
/// Needed whenever a catalogue's field list changes structurally (a field is added,
/// removed, or reordered), since `tiebreakKey` encodes "every other field, in priority
/// order" for each FieldValue — a change to that order or field set invalidates the
/// tiebreak key on every field's FieldValue for every item, not just the field that moved.
/// Equally whenever a field's display role or option set changes, since the facet mirrors
/// interpret values through that configuration. Also used by `DerivedDataBackfill` when an
/// encoding changes.
///
/// One sweep always refreshes every column: the compare-before-assign inside makes the extra
/// columns free for an item that doesn't need them, and a catalogue with 2000+ items
/// shouldn't be walked twice for one save.
///
/// Chunked and yielding, modeled on `CatalogueDTO.makeCatalogue`'s import batching.
enum CatalogueSortKeyMaintenance {

    @MainActor
    static func recomputeTiebreakKeys(
        for catalogue: Catalogue,
        in context: ModelContext,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async {
        await recomputeDerivedData(for: catalogue, in: context, onProgress: onProgress)
    }

    @MainActor
    static func recomputeFacets(
        for catalogue: Catalogue,
        in context: ModelContext,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async {
        await recomputeDerivedData(for: catalogue, in: context, onProgress: onProgress)
    }

    @MainActor
    static func recomputeDerivedData(
        for catalogue: Catalogue,
        in context: ModelContext,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async {
        let sortedDefs = catalogue.sortedFieldDefinitions
        let items = catalogue.items.filter { $0.deletedDate == nil }
        let total = items.count

        for (index, item) in items.enumerated() {
            ItemDerivedColumns.refresh(on: item, fieldValues: item.fieldValues, definitions: sortedDefs)

            onProgress?(index + 1, total)
            if index % 20 == 19 {
                await Task.yield()
            }
            if (index + 1) % 200 == 0 {
                try? context.save()
            }
        }
        try? context.save()
    }
}
