//
//  Item.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Field Type

/// The types of custom fields a user can add to a catalogue
enum FieldType: String, Codable, CaseIterable {
    case text = "Text"
    case number = "Number"
    case date = "Date"
    case boolean = "Yes/No"
    
    var icon: String {
        switch self {
        case .text: return "textformat"
        case .number: return "number"
        case .date: return "calendar"
        case .boolean: return "checkmark.circle"
        }
    }
}

// MARK: - Catalogue

/// Represents a collection (e.g., "Model Planes", "Stamp Collection")
@Model
final class Catalogue {
    var name: String
    var createdDate: Date
    var iconName: String // SF Symbol name
    var colorHex: String // Stored as hex string
    
    @Relationship(deleteRule: .cascade, inverse: \FieldDefinition.catalogue)
    var fieldDefinitions: [FieldDefinition] = []
    
    @Relationship(deleteRule: .cascade, inverse: \CatalogueItem.catalogue)
    var items: [CatalogueItem] = []
    
    init(name: String, iconName: String = "square.grid.2x2", colorHex: String = "#007AFF") {
        self.name = name
        self.createdDate = Date()
        self.iconName = iconName
        self.colorHex = colorHex
    }
    
    /// Returns only items that are owned (not wishlist)
    var ownedItems: [CatalogueItem] {
        items.filter { !$0.isWishlist }
    }
    
    /// Returns only wishlist items
    var wishlistItems: [CatalogueItem] {
        items.filter { $0.isWishlist }
    }
}
// MARK: - Field Definition

/// Defines a custom field that exists in a catalogue (e.g., "Year" as a Number field)
@Model
final class FieldDefinition {
    var name: String
    var fieldType: FieldType
    var sortOrder: Int // For ordering fields in the UI
    var catalogue: Catalogue?
    
    init(name: String, fieldType: FieldType, sortOrder: Int = 0) {
        self.name = name
        self.fieldType = fieldType
        self.sortOrder = sortOrder
    }
}

// MARK: - Catalogue Item

/// An individual item in a catalogue (can be owned or wishlist)
@Model
final class CatalogueItem {
    var createdDate: Date
    var isWishlist: Bool
    var notes: String? // Optional general notes field
    
    var catalogue: Catalogue?
    
    @Relationship(deleteRule: .cascade, inverse: \FieldValue.item)
    var fieldValues: [FieldValue] = []
    
    @Relationship(deleteRule: .cascade, inverse: \ItemPhoto.item)
    var photos: [ItemPhoto] = []
    
    init(isWishlist: Bool = false, notes: String? = nil) {
        self.createdDate = Date()
        self.isWishlist = isWishlist
        self.notes = notes
    }
    
    /// Get the value for a specific field by name
    func value(for fieldName: String) -> FieldValue? {
        fieldValues.first { $0.fieldName == fieldName }
    }
    
    /// Get the primary photo (first photo, or nil if none)
    var primaryPhoto: ItemPhoto? {
        photos.sorted { $0.sortOrder < $1.sortOrder }.first
    }
    
    /// A computed display name based on the first text field, or "Untitled"
    var displayName: String {
        // Try to find the first text field value
        if let firstText = fieldValues
            .filter({ $0.fieldType == .text })
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .first?.textValue,
           !firstText.isEmpty {
            return firstText
        }
        return "Untitled Item"
    }
}

// MARK: - Field Value

/// Stores the actual data for a field on a specific item
/// We store the field name and type here too (denormalized) so if the field definition
/// changes, old values still display correctly
@Model
final class FieldValue {
    var fieldName: String
    var fieldType: FieldType
    var sortOrder: Int
    
    // Value storage - only one will be used based on fieldType
    var textValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?
    
    var item: CatalogueItem?
    
    init(fieldName: String, fieldType: FieldType, sortOrder: Int = 0) {
        self.fieldName = fieldName
        self.fieldType = fieldType
        self.sortOrder = sortOrder
    }
    
    /// Convenience computed property to get/set the value based on type
    var value: Any? {
        get {
            switch fieldType {
            case .text: return textValue
            case .number: return numberValue
            case .date: return dateValue
            case .boolean: return boolValue
            }
        }
    }
    
    /// Set a value (type-safe)
    func setValue(_ value: Any?) {
        switch fieldType {
        case .text:
            textValue = value as? String
        case .number:
            numberValue = value as? Double
        case .date:
            dateValue = value as? Date
        case .boolean:
            boolValue = value as? Bool
        }
    }
    
    /// Get a formatted string representation of the value
    var displayValue: String {
        switch fieldType {
        case .text:
            return textValue ?? ""
        case .number:
            if let num = numberValue {
                return String(format: "%.2f", num)
            }
            return ""
        case .date:
            if let date = dateValue {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
            return ""
        case .boolean:
            return boolValue == true ? "Yes" : "No"
        }
    }
}

// MARK: - Item Photo

/// A photo attached to an item
@Model
final class ItemPhoto {
    var imageData: Data
    var sortOrder: Int
    var caption: String?
    
    var item: CatalogueItem?
    
    init(imageData: Data, sortOrder: Int = 0, caption: String? = nil) {
        self.imageData = imageData
        self.sortOrder = sortOrder
        self.caption = caption
    }
}

