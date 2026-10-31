//
//  BooleanOptions.swift
//  catalogue-it
//

import Foundation

// MARK: - Boolean Options

/// Not gated on the field's display role, so a field promoted to one later arrives with its
/// labels and appearance already set.
///
/// ⚠️ No explicit CodingKeys: they crash SwiftData's encoder for this stored blob.
nonisolated struct BooleanOptions: Codable, Equatable {
    var trueLabel: String? = nil
    var falseLabel: String? = nil
    var defaultValue: Bool = false

    /// SF Symbol marking the "on" value: a badge on rows and cards, beside the label on the
    /// item page, a tappable tile in the edit sheet, and the filter button's symbol. Independent
    /// of the display role, though a status-tab field never shows it. `nil` keeps the plain
    /// toggle and no badge; only the toolbar toggle, which must render something, substitutes
    /// `fallbackFilterIconName`. Named for its first use; renaming a stored property breaks
    /// decoding of existing rows.
    var flagIconName: String? = nil
    /// `nil` leaves the badge in the accent colour.
    var flagColorHex: String? = nil

    /// The multi-flag menu's symbol, so an unconfigured flag reads as "a filter".
    static let fallbackFilterIconName = "line.3.horizontal.decrease.circle"

    /// Blank labels fall back to the same "Yes"/"No" the field editor shows as placeholders.
    var resolvedLabels: (trueLabel: String, falseLabel: String) {
        let trueLabel = trueLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let falseLabel = falseLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            trueLabel: (trueLabel?.isEmpty == false ? trueLabel! : String(localized: "Yes")),
            falseLabel: (falseLabel?.isEmpty == false ? falseLabel! : String(localized: "No"))
        )
    }

    func label(for value: Bool) -> String {
        let labels = resolvedLabels
        return value ? labels.trueLabel : labels.falseLabel
    }
}
