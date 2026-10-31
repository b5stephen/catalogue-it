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

    /// A Yes/No field with an icon is a badge on rows and cards rather than a summary line, and a
    /// tappable tile in the edit sheet. The tab bar's chips stand in for it on a status field.
    var showsIconBadge: Bool {
        fieldType == .boolean && displayRole != .statusTabs && flagIconName != nil
    }

    /// Eligible for an item row's title and summary lines.
    var isSummaryField: Bool {
        displayRole == .none && !showsIconBadge
    }
}
