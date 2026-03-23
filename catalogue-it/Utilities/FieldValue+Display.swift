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
            switch opts.format {
            case .number:
                return value.formatted(.number.precision(.fractionLength(opts.precision)))
            case .currency:
                let code = Locale.current.currency?.identifier ?? "USD"
                return value.formatted(.currency(code: code).precision(.fractionLength(opts.precision)))
            }
        case .date:
            return dateValue.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        case .boolean:
            return boolValue == true ? "Yes" : "No"
        }
    }
}
