//
//  CatalogueItem.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData

// MARK: - Catalogue Item

/// An individual item in a catalogue
@Model
final class CatalogueItem {
    #Index<CatalogueItem>(
        [\.statusValue],
        [\.createdDate],
        [\.statusValue, \.createdDate],
        [\.deletedDate],
        [\.deletedDate, \.statusValue],
        [\.deletedDate, \.searchText],   // enables DB-level search combined with soft-delete filter
        // Catalogue-scoped compound indexes: the most common access pattern is
        // "items in catalogue X, not deleted, sorted by createdDate". Without these,
        // every fetchCount and paginated fetch must scan all non-deleted rows and
        // filter by catalogue FK in memory — O(n) scan + O(n log n) sort per page.
        // With these indexes SQLite can seek directly into the right range and return
        // rows in sorted order without a separate sort step.
        [\.catalogue, \.deletedDate, \.createdDate],
        [\.catalogue, \.deletedDate, \.statusValue, \.createdDate]
    )

    // Every stored property below carries a default value: CloudKit rejects
    // non-optional attributes that have none, and the container fails to build.
    var createdDate: Date = Date.now
    var notes: String? // Optional general notes field
    var deletedDate: Date? // nil = active; non-nil = soft deleted

    /// Lowercased, space-joined concatenation of all field display values.
    /// Updated on every item save via `SearchTextBuilder`. Enables DB-level CONTAINS predicate
    /// so non-matching items are never loaded into Swift memory during search.
    /// Adding with a default value requires no SchemaMigrationPlan; existing rows get "".
    var searchText: String = ""

    /// Denormalised mirror of this item's value for the catalogue's `.statusTabs` field.
    /// `""` when the catalogue has no status field or the item has no value for it.
    /// Maintained by `ItemFacetBuilder` on every write path — see that type for why the
    /// mirror exists rather than filtering through the `FieldValue` relationship.
    var statusValue: String = ""

    /// Denormalised mirror of this item's set `.flagFilter` fields, as concatenated
    /// `|<fieldID>|` tokens. `""` when no flags are set. Filtered with a CONTAINS
    /// predicate, the same mechanism `searchText` uses.
    var flagKeys: String = ""

    var isDeleted: Bool { deletedDate != nil }

    var catalogue: Catalogue?

    // Optional for CloudKit; read through the non-optional accessors below. See Catalogue.swift.
    @Relationship(deleteRule: .cascade, inverse: \FieldValue.item)
    var storedFieldValues: [FieldValue]? = []

    @Relationship(deleteRule: .cascade, inverse: \ItemPhoto.item)
    var storedPhotos: [ItemPhoto]? = []

    init(notes: String? = nil) {
        self.createdDate = Date.now
        self.notes = notes
    }

    /// Get the value for a specific field definition.
    /// Performs an O(n) in-memory linear scan over `fieldValues`.
    /// Not predicate-backed — safe because item field counts are small.
    func value(for definition: FieldDefinition) -> FieldValue? {
        fieldValues.first { $0.fieldDefinition == definition }
    }
}

// MARK: - Relationship Accessors

/// Non-optional views onto the CloudKit-mandated optional relationships.
/// Must stay in an extension — see the note in Catalogue.swift.
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
