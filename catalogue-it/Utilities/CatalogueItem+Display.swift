//
//  CatalogueItem+Display.swift
//  catalogue-it
//

import Foundation

// MARK: - Item Field Display

/// A Yes/No field has two states: no value, or no `FieldValue` at all (an item that predates the
/// field), reads as off. Read Yes/No fields through these, never `value(for:)?.boolValue`.
extension CatalogueItem {

    func isOn(_ definition: FieldDefinition) -> Bool {
        value(for: definition)?.boolValue == true
    }

    /// `""` when unset; a Yes/No field never is.
    func displayValue(for definition: FieldDefinition) -> String {
        if let value = value(for: definition) {
            return value.displayValue(options: definition.fieldOptions)
        }
        guard definition.fieldType == .boolean else { return "" }
        return (definition.booleanOptions ?? BooleanOptions()).label(for: false)
    }
}
