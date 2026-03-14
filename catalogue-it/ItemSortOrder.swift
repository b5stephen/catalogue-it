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
enum ItemSortField: Equatable {
    case dateAdded
    case name
    case field(String)

    static let dateAddedKey = "__dateAdded"
    static let nameKey      = "__name"

    init(rawValue: String) {
        switch rawValue {
        case Self.dateAddedKey: self = .dateAdded
        case Self.nameKey:      self = .name
        default:                self = .field(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .dateAdded:        Self.dateAddedKey
        case .name:             Self.nameKey
        case .field(let name):  name
        }
    }
}

// MARK: - Item Sort Direction

enum ItemSortDirection: String {
    case ascending  = "asc"
    case descending = "desc"
}
