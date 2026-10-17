//
//  CatalogueImporter.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 26/03/2026.
//

import Foundation
import SwiftData

// MARK: - Catalogue Importer

enum CatalogueImporter {
    /// - Parameters:
    ///   - priorityOffset: Pass `catalogues.count`, so imports append without colliding.
    ///   - onProgress: (completed, total) across all catalogues, on the main actor.
    @MainActor
    static func importCatalogues(
        from data: Data,
        into context: ModelContext,
        priorityOffset: Int,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> [Catalogue] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(CatalogueExportFile.self, from: data)
        // v1 files are upgraded during import; only newer formats are rejected.
        guard file.version <= CatalogueExportFile.currentVersion else {
            throw ImportError.unsupportedVersion(file.version)
        }
        let totalItems = file.catalogues.reduce(0) { $0 + $1.items.count }
        var completedBefore = 0
        var imported: [Catalogue] = []
        for dto in file.catalogues {
            let catalogue = await dto.makeCatalogue(
                in: context,
                priorityOffset: priorityOffset,
                onProgress: { current, _ in
                    onProgress?(completedBefore + current, totalItems)
                }
            )
            completedBefore += dto.items.count
            imported.append(catalogue)
        }
        return imported
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
