//
//  CatalogueExporter.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Catalogue Exporter

enum CatalogueExporter {
    // MARK: - JSON Export

    /// - Parameter includePhotos: `false` omits photos to keep the file small.
    static func jsonData(for catalogue: Catalogue, includePhotos: Bool = true) throws -> Data {
        let file = CatalogueExportFile(
            exportedAt: .now,
            catalogues: [CatalogueDTO(catalogue, includePhotos: includePhotos)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }
}

// MARK: - Export Format

enum CatalogueExportFormat: CaseIterable, Identifiable {
    case csv
    case jsonWithPhotos
    case jsonWithoutPhotos

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .csv: "Export as CSV"
        case .jsonWithPhotos: "Export as JSON (with Photos)"
        case .jsonWithoutPhotos: "Export as JSON (no Photos)"
        }
    }

    var systemImage: String {
        self == .csv ? "tablecells" : "doc.text"
    }

    func filename(for catalogue: Catalogue) -> String {
        self == .csv ? "\(catalogue.name).csv" : "\(catalogue.name).json"
    }

    /// Builds the file only when a share destination asks, as `ShareLink` would.
    func itemProvider(for catalogue: Catalogue, container: ModelContainer) -> NSItemProvider {
        let provider = NSItemProvider()
        let filename = filename(for: catalogue)
        // Built outside `register`, whose `@Sendable` autoclosure can't capture the model.
        switch self {
        case .csv:
            let file = CatalogueCSVFile(catalogue: catalogue, container: container, filename: filename)
            provider.register(file)
        case .jsonWithPhotos:
            let file = CatalogueJSONFile(catalogue: catalogue, includePhotos: true, filename: filename)
            provider.register(file)
        case .jsonWithoutPhotos:
            let file = CatalogueJSONFile(catalogue: catalogue, includePhotos: false, filename: filename)
            provider.register(file)
        }
        return provider
    }
}

// MARK: - Catalogue JSON File (Transferable)

// @unchecked Sendable: as CatalogueCSVFile.
struct CatalogueJSONFile: Transferable, @unchecked Sendable {
    let catalogue: Catalogue
    let includePhotos: Bool
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            try await MainActor.run { try CatalogueExporter.jsonData(for: file.catalogue, includePhotos: file.includePhotos) }
        }
        .suggestedFileName { $0.filename }
    }
}
