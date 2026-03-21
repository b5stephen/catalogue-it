//
//  ItemSortOrder.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import Foundation

// MARK: - Item Sort Field

/// Encodes the sort field selection as a plain string for `@AppStorage`.
/// Built-in sorts use a `__` prefix to avoid collisions with user-defined field names.
///
/// Declared `nonisolated` to opt out of the module's default `@MainActor` isolation,
/// so its `Hashable` conformance is usable from any actor context.
nonisolated enum ItemSortField: Hashable {
    case dateAdded
    case field(String)

    static let dateAddedKey = "__dateAdded"

    init(rawValue: String) {
        switch rawValue {
        case Self.dateAddedKey: self = .dateAdded
        default:                self = .field(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .dateAdded:        Self.dateAddedKey
        case .field(let name):  name
        }
    }
}

// MARK: - Item Sort Direction

enum ItemSortDirection: String {
    case ascending  = "asc"
    case descending = "desc"
}


