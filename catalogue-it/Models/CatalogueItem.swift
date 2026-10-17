//
//  CatalogueItem.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData

// MARK: - Catalogue Item

@Model
final class CatalogueItem {
    #Index<CatalogueItem>(
        [\.statusValue],
        [\.createdDate],
        [\.statusValue, \.createdDate],
        [\.deletedDate],
        [\.deletedDate, \.statusValue],
        [\.deletedDate, \.searchText],   // enables DB-level search combined with soft-delete filter
        // The common query is "items in catalogue X, not deleted, sorted by createdDate".
        // These let SQLite seek straight to that range in order, rather than scanning every
        // non-deleted row and sorting for each count and page.
        [\.catalogue, \.deletedDate, \.createdDate],
        [\.catalogue, \.deletedDate, \.statusValue, \.createdDate]
    )

    // Every stored property below carries a default value: CloudKit rejects
    // non-optional attributes that have none, and the container fails to build.
    var createdDate: Date = Date.now
    /// The user's last edit of fields, photos or notes — only `ItemSaveService` bumps it, never
    /// derived-column maintenance or soft delete. Also the key thumbnails reload on.
    var modifiedDate: Date = Date.now
    var notes: String?
    var deletedDate: Date? // nil = active; non-nil = soft deleted

    /// Built by `SearchTextBuilder`, so search is a CONTAINS predicate in the store.
    var searchText: String = ""

    /// Mirror of the `.statusTabs` field's value, maintained by `ItemFacetBuilder`.
    var statusValue: String = ""

    /// The set `.flagFilter` fields as `|<fieldID>|` tokens, matched with CONTAINS.
    var flagKeys: String = ""

    var isDeleted: Bool { deletedDate != nil }

    var catalogue: Catalogue?

    // Optional for CloudKit; use the accessors below.
    @Relationship(deleteRule: .cascade, inverse: \FieldValue.item)
    var storedFieldValues: [FieldValue]? = []

    @Relationship(deleteRule: .cascade, inverse: \ItemPhoto.item)
    var storedPhotos: [ItemPhoto]? = []

    init(notes: String? = nil) {
        let now = Date.now
        self.createdDate = now
        self.modifiedDate = now
        self.notes = notes
    }

    /// A linear scan of `fieldValues`, fine for an item's handful of fields. Should the item
    /// hold duplicates for the definition (a merge artefact), the same one is chosen on
    /// every device — see `SortKeyEncoder.preferredValue`.
    func value(for definition: FieldDefinition) -> FieldValue? {
        SortKeyEncoder.preferredValue(for: definition, among: fieldValues)
    }
}

// MARK: - Relationship Accessors

/// Must stay in an extension — see Catalogue.swift.
extension CatalogueItem {
    var fieldValues: [FieldValue] {
        get { storedFieldValues ?? [] }
        set { storedFieldValues = newValue }
    }

    var photos: [ItemPhoto] {
        get { storedPhotos ?? [] }
        set { storedPhotos = newValue }
    }
}
