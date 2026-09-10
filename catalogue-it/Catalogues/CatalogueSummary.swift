//
//  CatalogueSummary.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Catalogue Summary

/// The headline numbers shown on the Catalogues screen.
///
/// Counts here are `fetchCount` calls against indexed predicates — no `CatalogueItem` is ever
/// materialised, which is what keeps the entry screen cheap for a 2000-item catalogue.
///
/// Only the item total lives here, because only the item total applies to every catalogue.
/// Deliberately *not* offered: a status breakdown (a `.statusTabs` field is opt-in, so the
/// figures would be missing from most cards and the layout would shift between them), a photo
/// total (the predicate would have to hop `ItemPhoto → item → catalogue`, which no index covers,
/// making it an O(all photos) scan per card) and a "last updated" date (`createdDate` only
/// tracks additions, and a truthful modified date would mean a new model property, a schema
/// version and a CloudKit deploy).
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
}
