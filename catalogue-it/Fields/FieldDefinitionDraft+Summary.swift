//
//  FieldDefinitionDraft+Summary.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Row Summary

/// What a field row shows beneath the name. The type itself is conveyed by the row's tile.
extension FieldDefinitionDraft {
    var summary: String {
        switch fieldType {
        case .text:
            return String(localized: "Text")
        case .date:
            return String(localized: "Date")
        case .number:
            return numberSummary
        case .optionList:
            return optionListSummary
        case .boolean:
            let labels = booleanOptions.resolvedLabels
            return "\(labels.trueLabel) / \(labels.falseLabel)"
        }
    }

    /// Currency fields get their symbol; every other type its `FieldType.icon`.
    var tileSymbol: String {
        guard fieldType == .number, numberOptions.format == .currency else { return fieldType.icon }
        switch Locale.current.currency?.identifier {
        case "EUR": return "eurosign"
        case "GBP": return "sterlingsign"
        case "JPY", "CNY": return "yensign"
        case "INR": return "indianrupeesign"
        case "KRW": return "wonsign"
        default: return "dollarsign"
        }
    }

    /// So an unnamed field is still selectable, not a blank row.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Field") : trimmed
    }

    /// `nil` leaves it in the accent colour, as for `FieldDefinition.flagColor`.
    var flagColor: Color? {
        let hex = booleanOptions.flagColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hex, !hex.isEmpty else { return nil }
        return Color(hex: hex)
    }

    /// `nil` means no custom icon, as for `FieldDefinition.flagIconName`.
    var flagIconName: String? {
        let name = booleanOptions.flagIconName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    /// Currency shows a sample, whose symbol says more than words. A sample of a plain number
    /// reads as a real value ("Year · 1,249"), so those describe the format instead.
    private var numberSummary: String {
        if numberOptions.format == .currency {
            // Through the item screens' formatter, so the sample can't drift from real values.
            return "\(String(localized: "Currency")) · \(FieldValueFormatter.number(1249, options: numberOptions))"
        }
        let precision = numberOptions.precision
        var parts = [
            String(localized: "Number"),
            precision == 0 ? String(localized: "Whole")
                : precision == 1 ? String(localized: "1 decimal")
                : String(localized: "\(precision) decimals")
        ]
        if !numberOptions.usesGroupingSeparator {
            parts.append(String(localized: "No separator"))
        }
        return parts.joined(separator: " · ")
    }

    private var optionListSummary: String {
        let all = optionListOptions.options
        guard !all.isEmpty else { return String(localized: "No options yet") }

        let defaultValue = optionListOptions.defaultValue.flatMap { all.contains($0) ? $0 : nil }
        var names = all.sorted().filter { $0 != defaultValue }
        if let defaultValue {
            names.insert(String(localized: "\(defaultValue) (default)"), at: 0)
        }
        let count = all.count == 1 ? String(localized: "1 option") : String(localized: "\(all.count) options")
        return "\(count) · \(names.joined(separator: ", "))"
    }
}
