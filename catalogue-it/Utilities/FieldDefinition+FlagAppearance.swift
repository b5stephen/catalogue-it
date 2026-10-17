//
//  FieldDefinition+FlagAppearance.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Flag Appearance

/// Per field, so several flags on a catalogue stay distinguishable. No icon means no badge,
/// not a shared fallback symbol.
extension FieldDefinition {

    var flagIconName: String? {
        let name = booleanOptions?.flagIconName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    /// `nil` leaves it in the accent colour.
    var flagColor: Color? {
        let hex = booleanOptions?.flagColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hex, !hex.isEmpty else { return nil }
        return Color(hex: hex)
    }
}
