//
//  StatusTab.swift
//  catalogue-it
//

import Foundation

// MARK: - Status Tab

/// A selection in the item-list tab bar, derived at runtime from the catalogue's
/// `.statusTabs` field. Replaces the old hardcoded `ItemTab` (All/Owned/Wishlist).
///
/// `storedValue` is what gets compared against the denormalised
/// `CatalogueItem.statusValue` column, so it must match `ItemFacetBuilder`'s encoding.
// `nonisolated` because the project defaults to main-actor isolation: without it the
// synthesised Equatable conformance is main-actor-isolated and can't be used from the
// nonisolated SwiftData model extensions that derive tabs.
nonisolated enum StatusTab: Hashable, Codable {
    /// Synthetic tab matching every item regardless of status. Not a real option value.
    case all
    /// A single value of an `.optionList`-backed status field.
    case option(String)
    /// The `true` side of a `.boolean`-backed status field.
    case boolTrue
    /// The `false` side of a `.boolean`-backed status field.
    case boolFalse

    /// The `CatalogueItem.statusValue` this tab filters on, or `nil` for `.all`
    /// (which applies no status filter at all).
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

/// A tab rendered in the item-list picker: the selection plus its display treatment.
nonisolated struct StatusTabDescriptor: Identifiable, Hashable {
    let tab: StatusTab
    let label: String
    let systemImage: String

    var id: StatusTab { tab }
}
