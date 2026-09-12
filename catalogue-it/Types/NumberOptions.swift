//
//  NumberOptions.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 22/03/2026.
//

import Foundation

// MARK: - Number Options

/// Configuration options for a Number field.
///
/// ⚠️ Do NOT add explicit CodingKeys — synthesised Codable is required.
/// SwiftData encodes this as a blob; explicit keys crash the SwiftData encoder.
nonisolated struct NumberOptions: Codable, Equatable {
    var format: NumberFormat = .number
    var precision: Int = 0
    /// Backing store for `usesGroupingSeparator`. Optional only so that blobs written before
    /// the option existed still decode — synthesised Codable requires every non-optional key
    /// to be present. `nil` reads as `true`, which was the behaviour before the option was
    /// added. Read and write through `usesGroupingSeparator`.
    var storedUsesGroupingSeparator: Bool? = nil

    init(format: NumberFormat = .number, precision: Int = 0, usesGroupingSeparator: Bool = true) {
        self.format = format
        self.precision = precision
        self.storedUsesGroupingSeparator = usesGroupingSeparator
    }

    /// Whether thousands are separated — "1,234" when on, "1234" when off.
    var usesGroupingSeparator: Bool {
        get { storedUsesGroupingSeparator ?? true }
        set { storedUsesGroupingSeparator = newValue }
    }

    // Compares the effective value, so an old blob (nil) equals a freshly saved default (true).
    static func == (lhs: NumberOptions, rhs: NumberOptions) -> Bool {
        lhs.format == rhs.format
            && lhs.precision == rhs.precision
            && lhs.usesGroupingSeparator == rhs.usesGroupingSeparator
    }
}
