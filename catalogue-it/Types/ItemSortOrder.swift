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

// MARK: - Catalogue Item Comparator

/// `SortComparator` used by `Table(sortOrder:)` to drive column-header chevrons.
///
/// Declared `nonisolated` to opt both `Hashable` and `SortComparator` conformances
/// out of the module's default `@MainActor` isolation — required by `Table`'s
/// `Sendable` type-parameter constraint on the sort order array.
/// `CatalogueItem` / `FieldValue` are `@Model` types whose properties are also
/// accessible from nonisolated context, so `compare(_:_:)` works without hopping.
nonisolated struct CatalogueItemComparator: Hashable {
    let field: ItemSortField
    var order: SortOrder = .forward
}

extension CatalogueItemComparator: SortComparator {
    typealias Compared = CatalogueItem

    nonisolated func compare(_ lhs: CatalogueItem, _ rhs: CatalogueItem) -> ComparisonResult {
        func cmp<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
            a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
        }
        func flip(_ r: ComparisonResult) -> ComparisonResult {
            switch r {
            case .orderedAscending:  return .orderedDescending
            case .orderedDescending: return .orderedAscending
            case .orderedSame:       return .orderedSame
            @unknown default:        return .orderedSame
            }
        }

        switch field {
        case .dateAdded:
            let base = cmp(lhs.createdDate, rhs.createdDate)
            return order == .forward ? base : flip(base)

        case .name:
            let result = lhs.displayName.localizedCompare(rhs.displayName)
            return order == .forward ? result : flip(result)

        case .field(let name):
            let va = lhs.value(for: name)
            let vb = rhs.value(for: name)
            // nil always sorts last regardless of direction
            if va == nil, vb == nil { return .orderedSame }
            guard let va else { return .orderedDescending }
            guard let vb else { return .orderedAscending }
            let base: ComparisonResult
            switch va.fieldType {
            case .text:
                base = (va.textValue ?? "").localizedCompare(vb.textValue ?? "")
            case .number:
                base = cmp(va.numberValue ?? 0, vb.numberValue ?? 0)
            case .date:
                if let da = va.dateValue, let db = vb.dateValue {
                    base = cmp(da, db)
                } else {
                    base = va.dateValue != nil ? .orderedAscending : .orderedDescending
                }
            case .boolean:
                let ba = va.boolValue ?? false, bb = vb.boolValue ?? false
                base = ba == bb ? .orderedSame : ba ? .orderedDescending : .orderedAscending
            }
            return order == .forward ? base : flip(base)
        }
    }
}
