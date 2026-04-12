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
    /// Decodes a catalogue export JSON file and inserts the catalogues into the given context.
    /// - Parameters:
    ///   - data: Raw JSON data from a `.json` export file.
    ///   - context: The SwiftData context to insert models into.
    ///   - priorityOffset: Added to each catalogue's stored priority so imported catalogues
    ///     append after existing ones without colliding. Pass `catalogues.count`.
    ///   - onProgress: Called on the main actor after each item is processed.
    ///     Receives (completedItems, totalItems) across all imported catalogues.
    /// - Returns: The newly created `Catalogue` objects.
    @MainActor
    static func importCatalogues(
        from data: Data,
        into context: ModelContext,
        priorityOffset: Int,
        onProgress: ((Int, Int) -> Void)? = nil
    ) throws -> [Catalogue] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(CatalogueExportFile.self, from: data)
        guard file.version == 1 else {
            throw ImportError.unsupportedVersion(file.version)
        }
        let totalItems = file.catalogues.reduce(0) { $0 + $1.items.count }
        var completedBefore = 0
        var imported: [Catalogue] = []
        for dto in file.catalogues {
            let catalogue = dto.makeCatalogue(
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
