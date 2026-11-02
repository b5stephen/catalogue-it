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
        booleanOptions?.resolvedFlagIconName
    }

    /// `nil` leaves it in the accent colour.
    var flagColor: Color? {
        let hex = booleanOptions?.flagColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hex, !hex.isEmpty else { return nil }
        return Color(hex: hex)
    }

    /// See `DisplayRole.showsIconBadge`.
    var showsIconBadge: Bool {
        displayRole.showsIconBadge(fieldType: fieldType, flagIconName: flagIconName)
    }

    /// See `DisplayRole.isSummaryField`.
    var isSummaryField: Bool {
        displayRole.isSummaryField(fieldType: fieldType, flagIconName: flagIconName)
    }
}
