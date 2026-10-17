//
//  FieldValue.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData

// MARK: - Field Value

@Model
final class FieldValue {
    // Sorting by a custom field is a fetch of FieldValues for one definition in this order.
    #Index<FieldValue>([\.fieldDefinition, \.sortKey, \.tiebreakKey])

    // Every stored property below carries a default value: CloudKit rejects
    // non-optional attributes that have none, and the container fails to build.
    var fieldDefinition: FieldDefinition?
    var fieldType: FieldType = FieldType.text
    var item: CatalogueItem?

    // Only the one matching `fieldType` is set.
    var textValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?

    /// The value encoded to sort lexicographically (`SortKeyEncoder`); the default sentinel,
    /// for no value, sorts last.
    var sortKey: String = "\u{FFFF}"

    /// The item's other fields in priority order, then its `createdDate`, joined by
    /// `SortKeyEncoder.tiebreakSeparator`: the second sort descriptor, so ties on `sortKey`
    /// break the same way on every fetch.
    var tiebreakKey: String = "\u{FFFF}"

    init(fieldDefinition: FieldDefinition?, fieldType: FieldType) {
        self.fieldDefinition = fieldDefinition
        self.fieldType = fieldType
    }
}
