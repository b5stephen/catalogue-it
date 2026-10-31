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

    /// Currency fields get their symbol and Yes/No fields their icon; every other type its
    /// `FieldType.icon`.
    var tileSymbol: String {
        if showsIconBadge, let flagIconName { return flagIconName }
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

    /// As for `FieldDefinition.showsIconBadge`.
    var showsIconBadge: Bool {
        fieldType == .boolean && displayRole != .statusTabs && flagIconName != nil
    }

    /// As for `FieldDefinition.isSummaryField`.
    var isSummaryField: Bool {
        displayRole == .none && !showsIconBadge
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

    /// Longest first, for `ViewThatFits`: an option list drops trailing names for "+N", then all
    /// names, so it never truncates mid-name. Capped, since a row never fits more than a handful.
    var summaryVariants: [String] {
        guard fieldType == .optionList else { return [summary] }
        let names = optionListNames
        guard names.count > 1 else { return [optionListSummary(names, showing: names.count)] }
        return stride(from: min(names.count, 8), through: 1, by: -1).map { optionListSummary(names, showing: $0) }
            + [optionCount(names.count)]
    }

    private var optionListSummary: String {
        let names = optionListNames
        return optionListSummary(names, showing: names.count)
    }

    /// The default leads; the rest are alphabetical.
    private var optionListNames: [String] {
        let all = optionListOptions.options
        let defaultValue = optionListOptions.defaultValue.flatMap { all.contains($0) ? $0 : nil }
        var names = all.sorted().filter { $0 != defaultValue }
        if let defaultValue {
            names.insert(String(localized: "\(defaultValue) (default)"), at: 0)
        }
        return names
    }

    private func optionListSummary(_ names: [String], showing shown: Int) -> String {
        guard !names.isEmpty else { return String(localized: "No options yet") }

        var listed = names.prefix(shown).joined(separator: ", ")
        if shown < names.count {
            listed += ", " + String(localized: "+\(names.count - shown)")
        }
        return "\(optionCount(names.count)) · \(listed)"
    }

    private func optionCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 option") : String(localized: "\(count) options")
    }
}
