//
//  FieldDefinitionDraft.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import Foundation

// MARK: - Field Definition Draft

/// A lightweight, non-persisted representation of a field definition used during catalogue editing.
struct FieldDefinitionDraft: Identifiable {
    let id = UUID()
    var name: String
    var fieldType: FieldType
    var sortOrder: Int
}

// MARK: - Field Value Draft

/// Lightweight form state for a single field input during item editing.
struct FieldValueDraft: Identifiable {
    let id: UUID = UUID()
    let fieldName: String
    let fieldType: FieldType
    let sortOrder: Int

    var textValue: String = ""
    var numberText: String = ""   // String binding; parsed to Double on save
    var dateValue: Date = .now
    var boolValue: Bool = false
}

// MARK: - Photo Draft

/// Lightweight form state for a photo during item editing.
struct PhotoDraft: Identifiable {
    let id: UUID = UUID()
    var imageData: Data
    var caption: String = ""
    var sortOrder: Int
}
