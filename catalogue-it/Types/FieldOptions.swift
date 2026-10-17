//
//  FieldOptions.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 22/03/2026.
//

import Foundation

// MARK: - Field Options

/// Only the case matching the field's `fieldType` is stored.
///
/// ⚠️ Never rename a case: the labels are the stored Codable keys.
///
/// ⚠️ `nonisolated` is load-bearing, here and on every type this wraps: an isolated
/// `Codable` conformance is invisible off the main actor, where SwiftData may encode, and the
/// column is saved as NULL. `FieldOptionsPersistenceTests` guards it.
nonisolated enum FieldOptions: Codable, Equatable {
    case number(NumberOptions)
    case optionList(OptionListOptions)
    case boolean(BooleanOptions)
}
