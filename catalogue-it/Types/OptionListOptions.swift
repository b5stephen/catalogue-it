//
//  OptionListOptions.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 12/04/2026.
//

import Foundation

// MARK: - Option List Options

/// Configuration for an Option List field.
///
/// `options` is stored in insertion order; display always sorts alphabetically.
/// `defaultValue` must be one of `options` or nil — callers are responsible for
/// enforcing this invariant when mutating.
///
/// ⚠️ Do NOT add explicit CodingKeys — synthesised Codable is required.
/// SwiftData encodes this as a blob; explicit keys crash the SwiftData encoder.
struct OptionListOptions: Codable, Equatable {
    var options: [String] = []
    var defaultValue: String? = nil
}
