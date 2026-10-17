//
//  OptionListOptions.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 12/04/2026.
//

import Foundation

// MARK: - Option List Options

/// `options` is in insertion order; display sorts alphabetically. `defaultValue` must be one
/// of `options` or nil — callers keep that true.
///
/// ⚠️ No explicit CodingKeys: they crash SwiftData's encoder for this stored blob. And keep it
/// `nonisolated` — see `FieldOptions`.
nonisolated struct OptionListOptions: Codable, Equatable {
    var options: [String] = []
    var defaultValue: String? = nil
}
