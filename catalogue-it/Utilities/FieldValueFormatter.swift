//
//  FieldValueFormatter.swift
//  catalogue-it
//

import Foundation

// MARK: - Field Value Formatter

/// Formats stored field values for display.
///
/// Owned separately from `FieldValue` so the field-configuration previews can format a
/// sample value — which has no `FieldValue` record behind it — through exactly the code
/// that will format the real thing.
///
/// `nonisolated` because `FieldValue.displayValue` is: formatting runs wherever a value is
/// being read, including off the main actor.
nonisolated enum FieldValueFormatter {
    static func number(_ value: Double, options: NumberOptions) -> String {
        switch options.format {
        case .number:
            return value.formatted(.number.precision(.fractionLength(options.precision)))
        case .currency:
            let code = Locale.current.currency?.identifier ?? "USD"
            return value.formatted(.currency(code: code).precision(.fractionLength(options.precision)))
        }
    }

    static func date(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .omitted)
    }

    static func boolean(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }
}
