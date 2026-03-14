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
/// We store the field name and type here too (denormalized) so if the field definition
/// changes, old values still display correctly.
@Model
final class FieldValue {
    var fieldName: String
    var fieldType: FieldType
    var sortOrder: Int

    // Value storage — only one will be used based on fieldType
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

    /// Convenience computed property to get the value based on type
    var value: Any? {
        switch fieldType {
        case .text: textValue
        case .number: numberValue
        case .date: dateValue
        case .boolean: boolValue
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
            textValue ?? ""
        case .number:
            numberValue.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? ""
        case .date:
            dateValue.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        case .boolean:
            boolValue == true ? "Yes" : "No"
        }
    }
}
