//
//  StatusTab.swift
//  catalogue-it
//

import Foundation

// MARK: - Status Tab

/// `storedValue` must match `ItemFacetBuilder`'s encoding of `CatalogueItem.statusValue`.
nonisolated enum StatusTab: Hashable, Codable {
    case all
    case option(String)
    case boolTrue
    case boolFalse

    var storedValue: String? {
        switch self {
        case .all:            nil
        case .option(let v):  v
        case .boolTrue:       ItemFacetBuilder.boolTrueToken
        case .boolFalse:      ItemFacetBuilder.boolFalseToken
        }
    }
}

// MARK: - Status Tab Descriptor

nonisolated struct StatusTabDescriptor: Identifiable, Hashable {
    let tab: StatusTab
    let label: String
    let systemImage: String

    var id: StatusTab { tab }
}
