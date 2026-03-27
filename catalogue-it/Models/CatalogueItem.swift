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
    #Index<CatalogueItem>([\.isWishlist], [\.createdDate], [\.isWishlist, \.createdDate], [\.deletedDate], [\.deletedDate, \.isWishlist])

    var createdDate: Date
    var isWishlist: Bool
    var notes: String? // Optional general notes field
    var deletedDate: Date? // nil = active; non-nil = soft deleted

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
