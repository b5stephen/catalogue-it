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
    @Relationship(deleteRule: .nullify, inverse: \FieldValue.fieldDefinition)
    var fieldValues: [FieldValue] = []

    init(name: String, fieldType: FieldType, priority: Int = 0, fieldID: UUID = UUID()) {
        self.fieldID = fieldID
        self.name = name
        self.fieldType = fieldType
        self.priority = priority
    }

    /// Convenience accessor for Number field options.
    /// Returns `nil` for non-number fields; callers should handle the optional explicitly.
    var numberOptions: NumberOptions? {
        get {
            if case .number(let opts) = fieldOptions { return opts }
            return nil
        }
        set {
            guard fieldType == .number else { return }
            fieldOptions = newValue.map { .number($0) }
        }
    }

    /// Convenience accessor for Option List field options.
    /// Returns `nil` for non-optionList fields; callers should handle the optional explicitly.
    var optionListOptions: OptionListOptions? {
        get {
            if case .optionList(let opts) = fieldOptions { return opts }
            return nil
        }
        set {
            guard fieldType == .optionList else { return }
            fieldOptions = newValue.map { .optionList($0) }
        }
    }
}
