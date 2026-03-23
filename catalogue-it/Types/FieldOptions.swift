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
/// Coding keys are pinned explicitly to prevent on-disk key changes if
/// case names are ever renamed or new cases are added.
enum FieldOptions: Codable, Equatable {
    case number(NumberOptions)
    // future: case date(DateOptions)

    private enum CodingKeys: String, CodingKey {
        case number = "number"
        // future: case date = "date"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let opts):
            try container.encode(opts, forKey: .number)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let opts = try container.decodeIfPresent(NumberOptions.self, forKey: .number) {
            self = .number(opts)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown FieldOptions variant")
        )
    }
}
