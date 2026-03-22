//
//  FieldDefinitionDraft.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import Foundation
import SwiftData

// MARK: - Field Definition Draft

/// A lightweight, non-persisted representation of a field definition used during catalogue editing.
struct FieldDefinitionDraft: Identifiable {
    let id: UUID = UUID() // SwiftUI list identity only
    var existingDefinition: FieldDefinition? // nil = new field being added
    var name: String
    var fieldType: FieldType
    var priority: Int
    var numberOptions: NumberOptions = NumberOptions()
}

// MARK: - Field Value Draft

/// Lightweight form state for a single field input during item editing.
struct FieldValueDraft: Identifiable {
    let id: UUID = UUID()
    let fieldDefinition: FieldDefinition
    let fieldType: FieldType

    var textValue: String = ""
    var numberValue: Double? = nil
    var dateValue: Date? = nil
    var boolValue: Bool = false
}

// MARK: - Photo Draft

/// Lightweight form state for a photo during item editing.
struct PhotoDraft: Identifiable {
    let id: UUID = UUID()
    var imageData: Data
    var caption: String = ""
    var priority: Int
}
