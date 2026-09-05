//
//  FieldDefinition+FlagAppearance.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Flag Appearance

/// How a `.flagFilter` field draws itself, in the toolbar toggle and on item rows and cards.
///
/// Configurable per field so several flags on one catalogue stay distinguishable — a row
/// carrying three identical yellow stars tells the user nothing about which flags are set.
///
/// Both are genuinely optional: a field with no icon draws no badge at all, rather than
/// falling back to a shared symbol that would make every flag look alike.
extension FieldDefinition {

    /// SF Symbol for this flag's badge, or `nil` when the user has set none — in which case
    /// item rows and cards draw nothing for it.
    var flagIconName: String? {
        let name = booleanOptions?.flagIconName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    /// Tint for this flag, or `nil` to leave it in the app's accent colour.
    var flagColor: Color? {
        let hex = booleanOptions?.flagColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hex, !hex.isEmpty else { return nil }
        return Color(hex: hex)
    }
}
