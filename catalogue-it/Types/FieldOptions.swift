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
enum FieldOptions: Codable, Equatable {
    case number(NumberOptions)
    // future: case date(DateOptions)
}
