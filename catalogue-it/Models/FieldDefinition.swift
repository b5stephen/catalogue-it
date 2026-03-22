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
    var priority: Int // For ordering fields in the UI
    var fieldOptions: FieldOptions? // Type-specific configuration; only set when the field type has options
    var catalogue: Catalogue?

    init(name: String, fieldType: FieldType, priority: Int = 0, fieldID: UUID = UUID()) {
        self.fieldID = fieldID
        self.name = name
        self.fieldType = fieldType
        self.priority = priority
    }

    /// Convenience accessor for Number field options.
    /// Returns defaults when `fieldOptions` is nil or a non-`.number` case.
    var numberOptions: NumberOptions {
        get {
            if case .number(let opts) = fieldOptions { return opts }
            return NumberOptions()
        }
        set {
            guard fieldType == .number else { return }
            fieldOptions = .number(newValue)
        }
    }
}
