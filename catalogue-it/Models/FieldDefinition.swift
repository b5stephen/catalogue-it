//
//  FieldDefinition.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData

// MARK: - Field Definition

/// Defines a custom field that exists in a catalogue (e.g., "Year" as a Number field)
@Model
final class FieldDefinition {
    var fieldID: UUID // Stable identifier used for AppStorage-persisted sort preferences
    var name: String
    var fieldType: FieldType
    var sortOrder: Int // For ordering fields in the UI
    var catalogue: Catalogue?

    init(name: String, fieldType: FieldType, sortOrder: Int = 0, fieldID: UUID = UUID()) {
        self.fieldID = fieldID
        self.name = name
        self.fieldType = fieldType
        self.sortOrder = sortOrder
    }
}
