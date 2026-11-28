//
//  DataFileWriter.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Data File Request

struct DataFileRequest: Sendable {
    let catalogueID: PersistentIdentifier
    let itemIDs: [PersistentIdentifier]
    var includesPhotos = true
    /// Written into the file and its name.
    var exportedAt = Date.now
}

// MARK: - Data File Writer

/// Builds the Data export: a `CatalogueExportFile` that `CatalogueImporter` reads back as a new
/// catalogue. Items are encoded and written a batch at a time, each batch on a fresh context, so
/// photo data is released as it goes rather than held for the whole file. Enter with
/// `Task.detached`, as for `SpreadsheetWriter`.
@ModelActor
actor DataFileWriter {
    /// Small, because an item's photos can run to several megabytes.
    private static let batchSize = 20

    enum WriterError: Error {
        case catalogueMissing
        case unexpectedLayout
    }

    /// A JSON file in a fresh temporary directory, removed again if the write fails or is
    /// cancelled.
    func write(_ request: DataFileRequest, onProgress: SpreadsheetWriter.Progress = { _, _ in }) throws -> URL {
        guard let catalogue = modelContext.model(for: request.catalogueID) as? Catalogue else {
            throw WriterError.catalogueMissing
        }
        let encoder = Self.encoder()
        let (head, tail) = try Self.envelope(around: catalogue, exportedAt: request.exportedAt, encoder: encoder)
        let wholeCatalogue = try request.itemIDs.count == liveItemCount(of: catalogue)

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(path: Self.fileName(
            catalogueName: catalogue.name,
            itemCount: wholeCatalogue ? nil : request.itemIDs.count,
            exportedAt: request.exportedAt
        ))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.write(contentsOf: head)

            let total = request.itemIDs.count
            onProgress(0, total)
            var isFirst = true
            for start in stride(from: 0, to: total, by: Self.batchSize) {
                try Task.checkCancellation()
                let ids = Array(request.itemIDs[start..<min(start + Self.batchSize, total)])
                var chunk = Data()
                for item in try items(ids, in: ModelContext(modelContainer)) {
                    if !isFirst { chunk.append(UInt8(ascii: ",")) }
                    isFirst = false
                    chunk.append(try encoder.encode(CatalogueItemDTO(item, includePhotos: request.includesPhotos)))
                }
                try handle.write(contentsOf: chunk)
                onProgress(start + ids.count, total)
            }
            try handle.write(contentsOf: tail)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return url
    }

    /// A count query, so no image data is loaded.
    func photoCount(itemIDs: [PersistentIdentifier]) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ItemPhoto>(predicate: #Predicate { photo in
            photo.item.flatMap { itemIDs.contains($0.persistentModelID) } == true
        }))
    }

    // MARK: Encoding

    nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// The file before and after its items: the envelope encoded with no items, split at the
    /// empty array. Not pretty-printed, so the marker has one spelling; a quote inside a string
    /// value is escaped, so only the key itself can match.
    nonisolated static func envelope(
        around catalogue: Catalogue, exportedAt: Date, encoder: JSONEncoder
    ) throws -> (head: Data, tail: Data) {
        let file = CatalogueExportFile(exportedAt: exportedAt, catalogues: [CatalogueDTO(catalogue, items: [])])
        let encoded = try encoder.encode(file)
        let marker = Data(#""items":[]"#.utf8)
        guard let range = encoded.firstRange(of: marker),
              encoded[range.upperBound...].firstRange(of: marker) == nil else {
            throw WriterError.unexpectedLayout
        }
        return (
            encoded[..<range.lowerBound] + Data(#""items":["#.utf8),
            Data("]".utf8) + encoded[range.upperBound...]
        )
    }

    /// The item count is named only when the file holds part of the catalogue.
    nonisolated static func fileName(
        catalogueName: String, itemCount: Int?, exportedAt: Date, timeZone: TimeZone = .current
    ) -> String {
        let qualifier: String? = switch itemCount {
        case nil: nil
        case 1: "1 item"
        case let count?: "\(count) items"
        }
        return ExportFileName.make(
            catalogueName: catalogueName,
            qualifier: qualifier,
            exportedAt: exportedAt,
            timeZone: timeZone,
            pathExtension: "json"
        )
    }

    // MARK: Fetching

    private func liveItemCount(of catalogue: Catalogue) throws -> Int {
        let id = catalogue.persistentModelID
        return try modelContext.fetchCount(FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == id && $0.deletedDate == nil }))
    }

    /// In `ids` order; an item deleted since the caller listed it is skipped.
    private func items(_ ids: [PersistentIdentifier], in context: ModelContext) throws -> [CatalogueItem] {
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: #Predicate {
            ids.contains($0.persistentModelID) && $0.deletedDate == nil
        })
        descriptor.relationshipKeyPathsForPrefetching = [\.storedFieldValues, \.storedPhotos]
        let fetched = try context.fetch(descriptor)
        let byID = Dictionary(fetched.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }
}
