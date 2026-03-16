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
    var createdDate: Date
    var isWishlist: Bool
    var notes: String? // Optional general notes field

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

    /// Get the value for a specific field by name
    func value(for fieldName: String) -> FieldValue? {
        fieldValues.first { $0.fieldName == fieldName }
    }

    /// Get the primary photo (lowest sortOrder), or nil if none
    var primaryPhoto: ItemPhoto? {
        photos.min(by: { $0.sortOrder < $1.sortOrder })
    }

    /// A computed display name based on the first field (by catalogue sortOrder), or "Untitled"
    var displayName: String {
        guard let catalogue,
              let firstField = catalogue.fieldDefinitions
                  .sorted(by: { $0.sortOrder < $1.sortOrder })
                  .first,
              let value = fieldValues.first(where: { $0.fieldName == firstField.name }),
              !value.displayValue.isEmpty
        else { return "Untitled Item" }
        return value.displayValue
    }
}
