//
//  CatalogueSummary.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Catalogue Summary

/// `fetchCount`s on indexed predicates only, so no item is materialised on the entry screen.
/// Deliberately just the total: a status breakdown would be missing from most cards, a photo
/// total has no covering index, and the model has no catalogue-level modified date.
enum CatalogueSummary {

    /// Backed by `#Index([\.catalogue, \.deletedDate, \.createdDate])`.
    static func itemCount(for catalogue: Catalogue, in context: ModelContext) -> Int {
        let id = catalogue.persistentModelID
        let descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == id && $0.deletedDate == nil }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
