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
        let blob = fieldValues
            .map { $0.displayValue() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
        // Unbounded by construction, and it shares a 1 MB CloudKit record with everything else
        // on the item. Recorded so the diagnostics screen can confirm or rule out record size
        // as a cause; the guard inside keeps this free below the threshold.
        SyncDiagnostics.noteFieldSize("CatalogueItem.searchText", blob.utf8.count)
        return blob
    }
}
