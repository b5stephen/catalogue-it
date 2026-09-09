//
//  CatalogueSummary.swift
//  catalogue-it
//

import SwiftUI
import SwiftData

// MARK: - Status Count

/// One status tab's share of a catalogue, ready to render as a chip.
struct CatalogueStatusCount: Identifiable {
    let label: String
    let count: Int
    let tint: Color

    var id: String { label }
}

// MARK: - Catalogue Summary

/// The headline numbers shown on the My Catalogues screen.
///
/// Every count here is a `fetchCount` against an indexed predicate — no `CatalogueItem` is ever
/// materialised, which is what keeps the entry screen cheap for a 2000-item catalogue. In
/// particular, `statusCounts` leans on the denormalised `CatalogueItem.statusValue` mirror and
/// the `[\.catalogue, \.deletedDate, \.statusValue, \.createdDate]` index, so each status is a
/// direct seek rather than a scan.
///
/// Deliberately *not* offered here: a photo total (the predicate would have to hop
/// `ItemPhoto → item → catalogue`, which no index covers, making it an O(all photos) scan per
/// card) and a "last updated" date (`createdDate` only tracks additions, and a truthful
/// modified date would mean a new model property, a schema version and a CloudKit deploy).
enum CatalogueSummary {

    /// Active (non-soft-deleted) item count.
    /// Backed by `#Index([\.catalogue, \.deletedDate, \.createdDate])`.
    static func itemCount(for catalogue: Catalogue, in context: ModelContext) -> Int {
        let id = catalogue.persistentModelID
        let descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == id && $0.deletedDate == nil }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Per-status counts for the catalogue's status field, in the user's own tab order.
    ///
    /// Empty statuses are dropped before the cap is applied, so a catalogue with five options
    /// and two in use shows the two that mean something rather than three, two of them zero.
    /// Returns `[]` when the catalogue has no status field — the card then shows the item
    /// total alone.
    static func statusCounts(
        for catalogue: Catalogue,
        in context: ModelContext,
        limit: Int = AppConstants.CatalogueCard.maxStatusChips
    ) -> [CatalogueStatusCount] {
        guard let field = catalogue.statusField else { return [] }
        let id = catalogue.persistentModelID

        let counts: [CatalogueStatusCount] = catalogue.statusTabDescriptors.compactMap { descriptor in
            // The synthetic "All" tab has no stored value; it would only restate the item total.
            guard let stored = descriptor.tab.storedValue else { return nil }
            let fetchDescriptor = FetchDescriptor<CatalogueItem>(
                predicate: #Predicate<CatalogueItem> {
                    $0.catalogue?.persistentModelID == id
                        && $0.deletedDate == nil
                        && $0.statusValue == stored
                }
            )
            let count = (try? context.fetchCount(fetchDescriptor)) ?? 0
            guard count > 0 else { return nil }
            return CatalogueStatusCount(
                label: descriptor.label,
                count: count,
                tint: field.statusChipTint(for: stored)
            )
        }

        return Array(counts.prefix(limit))
    }
}
