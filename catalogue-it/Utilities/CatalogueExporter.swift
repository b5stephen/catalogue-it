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

/// The "Back Up Catalogue" entries, for moving a catalogue to another device.
enum CatalogueExportFormat: CaseIterable, Identifiable {
    case jsonWithPhotos
    case jsonWithoutPhotos

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .jsonWithPhotos: "With Photos"
        case .jsonWithoutPhotos: "Without Photos"
        }
    }

    var systemImage: String { "doc.text" }

    func filename(for catalogue: Catalogue) -> String { "\(catalogue.name).json" }

    /// Builds the file only when a share destination asks, as `ShareLink` would.
    func itemProvider(for catalogue: Catalogue) -> NSItemProvider {
        let provider = NSItemProvider()
        // Built outside `register`, whose `@Sendable` autoclosure can't capture the model.
        let file = CatalogueJSONFile(catalogue: catalogue, includePhotos: self == .jsonWithPhotos, filename: filename(for: catalogue))
        provider.register(file)
        return provider
    }
}

// MARK: - Catalogue JSON File (Transferable)

// @unchecked Sendable: the catalogue is read on the main actor when the share destination asks.
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
