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

    /// SF Symbol for a `.flagFilter` field. `nil` means no badge on rows and cards; only the
    /// toolbar toggle, which must render something, substitutes `fallbackFilterIconName`.
    var flagIconName: String? = nil
    /// `nil` leaves the badge in the accent colour.
    var flagColorHex: String? = nil

    /// The multi-flag menu's symbol, so an unconfigured flag reads as "a filter".
    static let fallbackFilterIconName = "line.3.horizontal.decrease.circle"
}
