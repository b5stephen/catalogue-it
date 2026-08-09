//
//  BooleanOptions.swift
//  catalogue-it
//

import Foundation

// MARK: - Boolean Options

/// Configuration for a Yes/No field.
///
/// `trueLabel` / `falseLabel` are only meaningful when the field's `displayRole`
/// is `.statusTabs`, where they name the two tabs. When unset they fall back to
/// the field name and "Other" respectively — see `FieldDefinition.statusTabLabels`.
///
/// ⚠️ Do NOT add explicit CodingKeys — synthesised Codable is required.
/// SwiftData encodes this as a blob; explicit keys crash the SwiftData encoder.
nonisolated struct BooleanOptions: Codable, Equatable {
    var trueLabel: String? = nil
    var falseLabel: String? = nil
    /// Value new items start with.
    var defaultValue: Bool = false

    /// SF Symbol for a `.flagFilter` field's toolbar toggle and item-row badge.
    /// `nil` uses `defaultFlagIconName` — stored as an Optional so blobs written before
    /// this property existed still decode.
    var flagIconName: String? = nil
    /// Tint for the same, as a hex string. `nil` uses `defaultFlagColorHex`.
    var flagColorHex: String? = nil

    /// The star/yellow pairing the flag filter shipped with, and what every flag falls back
    /// to. Kept here so the fallback is defined once rather than at each render site.
    static let defaultFlagIconName = "star.fill"
    static let defaultFlagColorHex = "#FFCC00"
}
