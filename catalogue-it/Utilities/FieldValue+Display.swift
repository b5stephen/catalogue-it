//
//  FieldValue+Display.swift
//  catalogue-it
//

import Foundation

extension FieldValue {
    /// Pass the definition's `fieldOptions` to avoid faulting the relationship.
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
