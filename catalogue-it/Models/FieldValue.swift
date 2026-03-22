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
    var fieldDefinition: FieldDefinition?
    var fieldType: FieldType
    var item: CatalogueItem?

    // Value storage — only one will be used based on fieldType
    var textValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?

    init(fieldDefinition: FieldDefinition?, fieldType: FieldType) {
        self.fieldDefinition = fieldDefinition
        self.fieldType = fieldType
    }

    /// Get a formatted string representation of the value
    var displayValue: String {
        switch fieldType {
        case .text:
            textValue ?? ""
        case .number:
            numberValue.map { $0.formatted(.number.precision(.fractionLength(fieldDefinition?.precision ?? 0))) } ?? ""
        case .currency:
            numberValue.map {
                let code = Locale.current.currency?.identifier ?? "USD"
                return $0.formatted(.currency(code: code).precision(.fractionLength(fieldDefinition?.precision ?? 2)))
            } ?? ""
        case .date:
            dateValue.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        case .boolean:
            boolValue == true ? "Yes" : "No"
        }
    }
}
