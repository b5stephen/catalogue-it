//
//  FieldValueFormatter.swift
//  catalogue-it
//

import Foundation

// MARK: - Field Value Formatter

/// Apart from `FieldValue` so previews format a sample value through the same code.
/// `nonisolated` because `FieldValue.displayValue` is.
nonisolated enum FieldValueFormatter {
    static func number(_ value: Double, options: NumberOptions) -> String {
        let grouping: NumberFormatStyleConfiguration.Grouping = options.usesGroupingSeparator ? .automatic : .never
        switch options.format {
        case .number:
            return value.formatted(.number.precision(.fractionLength(options.precision)).grouping(grouping))
        case .currency:
            let code = Locale.current.currency?.identifier ?? "USD"
            return value.formatted(.currency(code: code).precision(.fractionLength(options.precision)).grouping(grouping))
        }
    }

    static func date(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .omitted)
    }
}
