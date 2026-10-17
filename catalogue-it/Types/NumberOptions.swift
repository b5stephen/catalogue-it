//
//  NumberOptions.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 22/03/2026.
//

import Foundation

// MARK: - Number Options

/// ⚠️ No explicit CodingKeys: they crash SwiftData's encoder for this stored blob.
nonisolated struct NumberOptions: Codable, Equatable {
    var format: NumberFormat = .number
    var precision: Int = 0
    /// Optional so blobs from before the option still decode; use `usesGroupingSeparator`.
    var storedUsesGroupingSeparator: Bool? = nil

    init(format: NumberFormat = .number, precision: Int = 0, usesGroupingSeparator: Bool = true) {
        self.format = format
        self.precision = precision
        self.storedUsesGroupingSeparator = usesGroupingSeparator
    }

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
