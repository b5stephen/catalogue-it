//
//  CatalogueSortKeyMaintenance.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Catalogue Sort Key Maintenance

/// Recomputes every derived column across a catalogue through `ItemDerivedColumns`. Needed
/// when fields are added, removed or reordered (every `tiebreakKey` encodes the others in
/// order), when a role or option set changes (facets read through them), and by
/// `DerivedDataBackfill`. Always refreshes every column in one sweep: compare-before-assign
/// makes the extra ones free. Chunked and yielding, like import.
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
