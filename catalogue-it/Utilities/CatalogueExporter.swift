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
    /// Generates a CSV string for all items in the catalogue.
    /// Columns: Tab, Name, [custom fields sorted by priority], Notes, Photo Count
    static func csvString(for catalogue: Catalogue) -> String {
        let fields = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
        var rows: [String] = []

        // Header row
        var headers = ["Tab"]
        headers.append(contentsOf: fields.map(\.name))
        headers.append(contentsOf: ["Notes", "Photo Count"])
        rows.append(headers.map(csvEscape).joined(separator: ","))

        // Data rows
        let allItems = catalogue.items.filter { $0.deletedDate == nil }.sorted { $0.createdDate < $1.createdDate }
        for item in allItems {
            var cells: [String] = []
            cells.append(item.isWishlist ? "Wishlist" : "Owned")
            for field in fields {
                let fv = item.value(for: field)
                let cell: String
                if let fv {
                    switch fv.fieldType {
                    case .text:
                        cell = fv.textValue ?? ""
                    case .number:
                        if let n = fv.numberValue {
                            cell = n.formatted(.number.grouping(.never))
                        } else {
                            cell = ""
                        }
                    case .date:
                        if let d = fv.dateValue {
                            cell = d.formatted(date: .abbreviated, time: .omitted)
                        } else {
                            cell = ""
                        }
                    case .boolean:
                        cell = fv.boolValue == true ? "Yes" : "No"
                    case .optionList:
                        cell = fv.textValue ?? ""
                    }
                } else {
                    cell = ""
                }
                cells.append(cell)
            }
            cells.append(item.notes ?? "")
            cells.append(item.photos.count.formatted())
            rows.append(cells.map(csvEscape).joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }

    /// Quotes a cell if it contains commas, double-quotes, or newlines.
    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    // MARK: - JSON Export

    /// Encodes a catalogue as a JSON export file.
    /// - Parameter includePhotos: When `false`, item photos are omitted to reduce file size.
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

// MARK: - Catalogue CSV File (Transferable)

// @unchecked Sendable: Catalogue is main-actor bound; DataRepresentation calls the
// exporting closure on the main actor before the share sheet appears, so this is safe.
struct CatalogueCSVFile: Transferable, @unchecked Sendable {
    let catalogue: Catalogue
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            let csv = await MainActor.run { CatalogueExporter.csvString(for: file.catalogue) }
            return Data(csv.utf8)
        }
        .suggestedFileName { $0.filename }
    }
}

// MARK: - Catalogue JSON File (Transferable)

// @unchecked Sendable: same reasoning as CatalogueCSVFile above.
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
