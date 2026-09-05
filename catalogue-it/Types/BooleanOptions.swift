//
//  BooleanOptions.swift
//  catalogue-it
//

import Foundation

// MARK: - Boolean Options

/// Configuration for a Yes/No field.
///
/// Every property here is editable on any Yes/No field, whatever display role the
/// catalogue's Options section has given it — `trueLabel` / `falseLabel` name the two tabs
/// when the field drives the tab bar, and the appearance is used when it drives a filter
/// toggle, but neither is gated on the role. A field promoted to a role later arrives with
/// its labels and appearance already set.
///
/// ⚠️ Do NOT add explicit CodingKeys — synthesised Codable is required.
/// SwiftData encodes this as a blob; explicit keys crash the SwiftData encoder.
nonisolated struct BooleanOptions: Codable, Equatable {
    var trueLabel: String? = nil
    var falseLabel: String? = nil
    /// Value new items start with.
    var defaultValue: Bool = false

    /// SF Symbol for a `.flagFilter` field's toolbar toggle and item-row badge.
    /// Optional in the real sense: `nil` means *no badge* on rows and cards, not a default
    /// symbol. Only the toolbar toggle — which must render something to be tappable —
    /// substitutes `fallbackFilterIconName`.
    var flagIconName: String? = nil
    /// Tint for the same, as a hex string. `nil` leaves the badge in the app's accent colour.
    var flagColorHex: String? = nil

    /// Stand-in symbol for the toolbar toggle of a flag with no icon of its own. Matches the
    /// symbol the multi-flag menu already uses, so an unconfigured flag reads as "a filter".
    static let fallbackFilterIconName = "line.3.horizontal.decrease.circle"
}
