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
extension FieldDefinition {

    /// SF Symbol for this flag, falling back to the default star.
    var flagIconName: String {
        let name = booleanOptions?.flagIconName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return BooleanOptions.defaultFlagIconName }
        return name
    }

    /// Tint for this flag, falling back to the default yellow.
    var flagColor: Color {
        Color(hex: booleanOptions?.flagColorHex ?? BooleanOptions.defaultFlagColorHex)
    }
}
