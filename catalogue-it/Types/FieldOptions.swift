//
//  FieldOptions.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 22/03/2026.
//

import Foundation

// MARK: - Field Options

/// Discriminated union of per-field-type configuration blobs.
/// Only the case matching a field's `fieldType` should be stored.
/// SwiftData encodes this as a Codable blob; `nil` on `FieldDefinition`
/// means the field type carries no configurable options.
///
/// ⚠️ IMPORTANT: Do NOT rename any case. Case names are the on-disk
/// Codable keys (Swift synthesizes them from the case label). Renaming
/// without a SchemaMigrationPlan will silently break stored data.
///
/// ⚠️ `nonisolated` is load-bearing, here and on every type this wraps. The project
/// defaults to main-actor isolation, and an isolated `Codable` conformance is invisible
/// (`as? any Encodable` is nil) on the executor SwiftData encodes on, so every save wrote
/// this column as NULL — wiping icons, labels, option lists and number formats.
/// `FieldOptionsPersistenceTests` guards it.
nonisolated enum FieldOptions: Codable, Equatable {
    case number(NumberOptions)
    // ⚠️ Do NOT rename this case — "optionList" is the permanent on-disk Codable key.
    case optionList(OptionListOptions)
    // ⚠️ Do NOT rename this case — "boolean" is the permanent on-disk Codable key.
    case boolean(BooleanOptions)
    // future: case date(DateOptions) — add matching "date" stability comment when added
}
