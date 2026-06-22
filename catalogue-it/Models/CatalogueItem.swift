//
//  CatalogueItem.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData

// MARK: - Catalogue Item

/// An individual item in a catalogue (can be owned or wishlist)
@Model
final class CatalogueItem {
    #Index<CatalogueItem>(
        [\.isWishlist],
        [\.createdDate],
        [\.isWishlist, \.createdDate],
        [\.deletedDate],
        [\.deletedDate, \.isWishlist],
        [\.deletedDate, \.searchText],   // enables DB-level search combined with soft-delete filter
        // Catalogue-scoped compound indexes: the most common access pattern is
        // "items in catalogue X, not deleted, sorted by createdDate". Without these,
        // every fetchCount and paginated fetch must scan all non-deleted rows and
        // filter by catalogue FK in memory — O(n) scan + O(n log n) sort per page.
        // With these indexes SQLite can seek directly into the right range and return
        // rows in sorted order without a separate sort step.
        [\.catalogue, \.deletedDate, \.createdDate],
        [\.catalogue, \.deletedDate, \.isWishlist, \.createdDate]
    )

    var createdDate: Date
    var isWishlist: Bool
    var notes: String? // Optional general notes field
    var deletedDate: Date? // nil = active; non-nil = soft deleted

    /// Lowercased, space-joined concatenation of all field display values.
    /// Updated on every item save via `SearchTextBuilder`. Enables DB-level CONTAINS predicate
    /// so non-matching items are never loaded into Swift memory during search.
    /// Adding with a default value requires no SchemaMigrationPlan; existing rows get "".
    var searchText: String = ""

    var isDeleted: Bool { deletedDate != nil }

    var catalogue: Catalogue?

    @Relationship(deleteRule: .cascade, inverse: \FieldValue.item)
    var fieldValues: [FieldValue] = []

    @Relationship(deleteRule: .cascade, inverse: \ItemPhoto.item)
    var photos: [ItemPhoto] = []

    init(isWishlist: Bool = false, notes: String? = nil) {
        self.createdDate = Date.now
        self.isWishlist = isWishlist
        self.notes = notes
    }

    /// Get the value for a specific field definition.
    /// Performs an O(n) in-memory linear scan over `fieldValues`.
    /// Not predicate-backed — safe because item field counts are small.
    func value(for definition: FieldDefinition) -> FieldValue? {
        fieldValues.first { $0.fieldDefinition == definition }
    }
}
