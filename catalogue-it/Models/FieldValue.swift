//
//  FieldValue.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData

// MARK: - Field Value

/// Stores the actual data for a field on a specific item.
/// References the FieldDefinition via a SwiftData relationship — renaming a field
/// requires no cascade update here.
@Model
final class FieldValue {
    // Compound index enables DB-level sort on a custom field:
    // fetch FieldValues WHERE fieldDefinition = X ORDER BY sortKey.
    #Index<FieldValue>([\.fieldDefinition, \.sortKey])

    var fieldDefinition: FieldDefinition?
    var fieldType: FieldType
    var item: CatalogueItem?

    // Value storage — only one will be used based on fieldType
    var textValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?

    /// Normalised, lexicographically sortable string computed from the typed value on save.
    /// `SortKeyEncoder.missingValueSentinel` ("\u{FFFF}") when the field has no value (sorts last).
    /// Adding with a default value requires no SchemaMigrationPlan; existing rows get the sentinel.
    var sortKey: String = SortKeyEncoder.missingValueSentinel

    init(fieldDefinition: FieldDefinition?, fieldType: FieldType) {
        self.fieldDefinition = fieldDefinition
        self.fieldType = fieldType
    }
}
