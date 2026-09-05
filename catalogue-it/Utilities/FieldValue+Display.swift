//
//  FieldValue+Display.swift
//  catalogue-it
//

import Foundation

extension FieldValue {
    /// Formatted string representation for display.
    /// Pass `fieldOptions` from the associated `FieldDefinition` to avoid faulting
    /// the `fieldDefinition` relationship. Safe to omit for non-configurable field types.
    func displayValue(options: FieldOptions? = nil) -> String {
        switch fieldType {
        case .text:
            return textValue ?? ""
        case .number:
            guard let value = numberValue else { return "" }
            let opts: NumberOptions
            if case .number(let o) = options { opts = o } else { opts = NumberOptions() }
            return FieldValueFormatter.number(value, options: opts)
        case .date:
            return dateValue.map { FieldValueFormatter.date($0) } ?? ""
        case .boolean:
            return FieldValueFormatter.boolean(boolValue == true)
        case .optionList:
            return textValue ?? ""
        }
    }
}
