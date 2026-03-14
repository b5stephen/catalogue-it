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
    /// Columns: Tab, Name, [custom fields sorted by sortOrder], Notes, Photo Count
    static func csvString(for catalogue: Catalogue) -> String {
        let fields = catalogue.fieldDefinitions.sorted { $0.sortOrder < $1.sortOrder }
        var rows: [String] = []

        // Header row
        var headers = ["Tab", "Name"]
        headers.append(contentsOf: fields.map(\.name))
        headers.append(contentsOf: ["Notes", "Photo Count"])
        rows.append(headers.map(csvEscape).joined(separator: ","))

        // Data rows
        let allItems = catalogue.items.sorted { $0.createdDate < $1.createdDate }
        for item in allItems {
            var cells: [String] = []
            cells.append(item.isWishlist ? "Wishlist" : "Owned")
            cells.append(item.displayName)
            for field in fields {
                let fv = item.value(for: field.name)
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
}

// MARK: - Catalogue CSV File (Transferable)

struct CatalogueCSVFile: Transferable {
    let content: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.content.utf8)
        }
        .suggestedFileName { file in
            file.filename
        }
    }
}
