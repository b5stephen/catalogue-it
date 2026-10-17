//
//  CatalogueLayoutOptions.swift
//  catalogue-it
//

import Foundation

// MARK: - Catalogue Layout Options

/// One JSON column (`Catalogue.layoutOptionsData`), so a new option needs no schema version
/// or CloudKit deploy; the blob merges as a single value across devices.
///
/// Decoded with `decodeIfPresent`, so an older build keeps what it understands of a newer
/// blob. (Custom decoding is fine: SwiftData stores this as `Data`.)
nonisolated struct CatalogueLayoutOptions: Equatable, Sendable {
    var detailLabelLayout: DetailLabelLayout = .beside
    var showPhotosInList: Bool = true

    init(detailLabelLayout: DetailLabelLayout = .beside, showPhotosInList: Bool = true) {
        self.detailLabelLayout = detailLabelLayout
        self.showPhotosInList = showPhotosInList
    }
}

nonisolated extension CatalogueLayoutOptions: Codable {
    private enum CodingKeys: String, CodingKey {
        case detailLabelLayout
        case showPhotosInList
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detailLabelLayout = try container.decodeIfPresent(DetailLabelLayout.self, forKey: .detailLabelLayout) ?? .beside
        showPhotosInList = try container.decodeIfPresent(Bool.self, forKey: .showPhotosInList) ?? true
    }
}

// MARK: - Detail Label Layout

nonisolated enum DetailLabelLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case beside
    case above

    var id: Self { self }

    var title: String {
        switch self {
        case .beside: String(localized: "Labels Beside Values")
        case .above: String(localized: "Labels Above Values")
        }
    }
}
