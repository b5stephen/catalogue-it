//
//  CatalogueImporter.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 26/03/2026.
//

import Foundation
import SwiftData

// MARK: - Catalogue Importer

nonisolated enum CatalogueImporter {

    /// Reads a Data file and upgrades v1 wishlists, so every caller sees v2 catalogues. Large
    /// with photos: call it off the main actor.
    static func decode(_ data: Data) throws -> CatalogueExportFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var file = try decoder.decode(CatalogueExportFile.self, from: data)
        // v1 files are upgraded here; only newer formats are rejected.
        guard file.version <= CatalogueExportFile.currentVersion else {
            throw ImportError.unsupportedVersion(file.version)
        }
        file.catalogues = file.catalogues.map { $0.upgradingLegacyWishlist() }
        return file
    }

    /// Every catalogue in the file as a new one, read back on the main context.
    @MainActor
    static func importCatalogues(
        from data: Data,
        into container: ModelContainer,
        priorityOffset: Int
    ) async throws -> [Catalogue] {
        let summary = try await Task.detached {
            let file = try decode(data)
            return try await ItemImporter(modelContainer: container)
                .importAsNewCatalogues(file, priorityOffset: priorityOffset)
        }.value
        return summary.catalogueIDs.compactMap { container.mainContext.model(for: $0) as? Catalogue }
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "This file uses format version \(v), which is newer than this version of Catalogue-It supports."
            }
        }
    }
}
