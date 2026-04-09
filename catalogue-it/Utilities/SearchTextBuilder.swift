//
//  SearchTextBuilder.swift
//  catalogue-it
//

import Foundation

// MARK: - Search Text Builder

/// Builds the denormalised search blob stored in `CatalogueItem.searchText`.
///
/// The blob is a lowercased, space-joined concatenation of all field display values.
/// Storing it on the item row allows SwiftData to push text search to SQLite via a
/// `CONTAINS` predicate — no item is loaded into Swift memory until a match is confirmed.
enum SearchTextBuilder {

    /// Builds a lowercased search blob from an array of `FieldValue`s.
    /// Call this after all field values for an item have been saved, then assign the
    /// result to `CatalogueItem.searchText`.
    static func build(from fieldValues: [FieldValue]) -> String {
        fieldValues
            .map { $0.displayValue() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
