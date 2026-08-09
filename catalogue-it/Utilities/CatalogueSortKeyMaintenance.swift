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
        await recomputeDerivedData(
            for: catalogue,
            in: context,
            tiebreakKeys: true,
            facets: false,
            onProgress: onProgress
        )
    }

    /// Rebuilds `CatalogueItem.statusValue` / `.flagKeys` across a whole catalogue.
    ///
    /// Needed whenever a field's display role or its option set changes: those columns are
    /// a denormalised mirror of field values interpreted through the field's configuration,
    /// so changing the configuration changes what the mirror should contain even though no
    /// item was edited. Without this, renaming a status option (or promoting a field to
    /// `.statusTabs`) would leave every existing item filtered into the wrong tab.
    @MainActor
    static func recomputeFacets(
        for catalogue: Catalogue,
        in context: ModelContext,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async {
        await recomputeDerivedData(
            for: catalogue,
            in: context,
            tiebreakKeys: false,
            facets: true,
            onProgress: onProgress
        )
    }

    /// Single chunked sweep over the catalogue's items, recomputing whichever derived data
    /// is requested. Both kinds are done in one pass when both are needed — a catalogue with
    /// 2000+ items shouldn't be walked twice for one save.
    @MainActor
    static func recomputeDerivedData(
        for catalogue: Catalogue,
        in context: ModelContext,
        tiebreakKeys: Bool,
        facets: Bool,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async {
        guard tiebreakKeys || facets else { return }

        let sortedDefs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
        let items = catalogue.items.filter { $0.deletedDate == nil }
        let total = items.count

        for (index, item) in items.enumerated() {
            let itemFieldValues = item.fieldValues

            if tiebreakKeys {
                for fv in itemFieldValues {
                    fv.tiebreakKey = SortKeyEncoder.tiebreakKey(
                        for: fv,
                        allFieldValuesOnItem: itemFieldValues,
                        fieldDefinitionsByPriority: sortedDefs,
                        itemCreatedDate: item.createdDate
                    )
                }
            }
            if facets {
                ItemFacetBuilder.apply(to: item, fieldValues: itemFieldValues, definitions: sortedDefs)
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
