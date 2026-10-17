//
//  ItemSortOrder.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import Foundation

// MARK: - Item Sort Field

/// Stored as a string on `Catalogue.sortFieldKey`: a field's UUID, or a `__`-prefixed key for
/// a built-in sort.
nonisolated enum ItemSortField: Hashable {
    case dateAdded
    case field(UUID)

    static let dateAddedKey = "__dateAdded"

    init(rawValue: String) {
        switch rawValue {
        case Self.dateAddedKey:
            self = .dateAdded
        default:
            if let uuid = UUID(uuidString: rawValue) {
                self = .field(uuid)
            } else {
                self = .dateAdded
            }
        }
    }

    var rawValue: String {
        switch self {
        case .dateAdded:          Self.dateAddedKey
        case .field(let fieldID): fieldID.uuidString
        }
    }
}

// MARK: - Item Sort Direction

enum ItemSortDirection: String {
    case ascending  = "asc"
    case descending = "desc"
}


