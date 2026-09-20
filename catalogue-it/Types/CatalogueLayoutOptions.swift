//
//  CatalogueLayoutOptions.swift
//  catalogue-it
//

import Foundation

// MARK: - Catalogue Layout Options

/// Per-catalogue display choices, persisted on `Catalogue` as one JSON column
/// (`layoutOptionsData`) rather than a column per option. Adding an option here is a struct
/// edit, not a schema version and a CloudKit deploy. The cost is that the blob merges as one
/// value across devices, which is acceptable for settings.
///
/// Every property has a default and is decoded with `decodeIfPresent`, so a build that
/// predates an option reads a blob written by a newer one and keeps what it understands.
/// (Custom decoding here is fine — it's `Data` to SwiftData, not a stored Codable type.)
nonisolated struct CatalogueLayoutOptions: Equatable, Sendable {
    /// Where a field's label sits against its value on the item detail screen.
    var detailLabelLayout: DetailLabelLayout = .beside

    init(detailLabelLayout: DetailLabelLayout = .beside) {
        self.detailLabelLayout = detailLabelLayout
    }
}

nonisolated extension CatalogueLayoutOptions: Codable {
    private enum CodingKeys: String, CodingKey {
        case detailLabelLayout
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detailLabelLayout = try container.decodeIfPresent(DetailLabelLayout.self, forKey: .detailLabelLayout) ?? .beside
    }
}

// MARK: - Detail Label Layout

/// A collection of short facts reads best as a two-column table; one of addresses and
/// descriptions reads best as headed paragraphs.
nonisolated enum DetailLabelLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Label left, value right on one line; long values wrap trailing-aligned.
    case beside
    /// Label above the value, everything left-aligned.
    case above

    var id: Self { self }

    var title: String {
        switch self {
        case .beside: String(localized: "Labels Beside Values")
        case .above: String(localized: "Labels Above Values")
        }
    }
}
