//
//  DataFileTestSupport.swift
//  UnitTests
//

import Foundation
import SwiftData
@testable import catalogue_it

/// Writes a Data export the way the composer does, then reads it back. Saves first: the writer
/// reads by identifier from its own context.
@MainActor
enum DataFileTestSupport {
    struct Written {
        let data: Data
        let fileName: String

        func decoded() throws -> CatalogueExportFile {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CatalogueExportFile.self, from: data)
        }
    }

    /// `items` defaults to the catalogue's live items, oldest first.
    static func write(
        _ catalogue: Catalogue,
        in container: ModelContainer,
        items: [CatalogueItem]? = nil,
        includesPhotos: Bool = true
    ) async throws -> Written {
        try container.mainContext.save()
        let chosen = items ?? catalogue.items
            .filter { $0.deletedDate == nil }
            .sorted { $0.createdDate < $1.createdDate }
        let request = DataFileRequest(
            catalogueID: catalogue.persistentModelID,
            itemIDs: chosen.map(\.persistentModelID),
            includesPhotos: includesPhotos
        )
        let url = try await DataFileWriter(modelContainer: container).write(request)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return Written(data: try Data(contentsOf: url), fileName: url.lastPathComponent)
    }
}
