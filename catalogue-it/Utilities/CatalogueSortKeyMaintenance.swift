//
//  CatalogueSortKeyMaintenance.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Catalogue Sort Key Maintenance

/// Recomputes `FieldValue.tiebreakKey` across a whole catalogue.
///
/// Needed whenever a catalogue's field list changes structurally (a field is added,
/// removed, or reordered), since `tiebreakKey` encodes "every other field, in priority
/// order" for each FieldValue — a change to that order or field set invalidates the
/// tiebreak key on every field's FieldValue for every item, not just the field that moved.
/// Also used for the one-time startup backfill of pre-existing data (see catalogue_itApp.swift).
///
/// Chunked and yielding, modeled on `CatalogueDTO.makeCatalogue`'s import batching, since
/// catalogues can hold 2000+ items.
enum CatalogueSortKeyMaintenance {

    @MainActor
    static func recomputeTiebreakKeys(
        for catalogue: Catalogue,
        in context: ModelContext,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async {
        let sortedDefs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
        let items = catalogue.items.filter { $0.deletedDate == nil }
        let total = items.count

        for (index, item) in items.enumerated() {
            let itemFieldValues = item.fieldValues
            for fv in itemFieldValues {
                fv.tiebreakKey = SortKeyEncoder.tiebreakKey(
                    for: fv,
                    allFieldValuesOnItem: itemFieldValues,
                    fieldDefinitionsByPriority: sortedDefs,
                    itemCreatedDate: item.createdDate
                )
            }
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
