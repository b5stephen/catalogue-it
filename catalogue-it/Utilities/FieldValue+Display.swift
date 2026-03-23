//
//  FieldValue+Display.swift
//  catalogue-it
//

import Foundation

extension FieldValue {
    /// Formatted string representation for display. Accessing this on a number
    /// field faults the `fieldDefinition` relationship — callers should ensure
    /// the relationship is pre-loaded where performance matters.
    var displayValue: String {
        switch fieldType {
        case .text:
            return textValue ?? ""
        case .number:
            guard let value = numberValue else { return "" }
            let opts = fieldDefinition?.numberOptions ?? NumberOptions()
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
