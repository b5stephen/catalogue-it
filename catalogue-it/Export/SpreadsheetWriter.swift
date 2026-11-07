//
//  SpreadsheetWriter.swift
//  catalogue-it
//

import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Spreadsheet Request

/// Everything the writer needs, as values that can cross to its context.
struct SpreadsheetRequest: Sendable {
    let catalogueID: PersistentIdentifier
    /// In the order the rows should come out.
    let itemIDs: [PersistentIdentifier]
    /// Unticked columns left out; a field that no longer exists is dropped by the writer.
    let columns: [ExportColumn]
    var options = SpreadsheetEncoding.Options()
    /// Names the file "<Catalogue> – Filtered.csv".
    var filtered = false
}

// MARK: - Spreadsheet Writer

/// Builds the Spreadsheet export on its own context, in batches. A ModelActor runs on the
/// calling task's thread, so enter it with `Task.detached` (as `BackgroundDeletionActor` does),
/// or this work lands on the main thread.
@ModelActor
actor SpreadsheetWriter {
    private static let batchSize = 200

    /// Called after each batch with rows done and the total, on the writer's thread.
    typealias Progress = @Sendable (_ done: Int, _ total: Int) -> Void

    enum WriterError: Error {
        case catalogueMissing
    }

    /// Non-deleted items in `createdDate` order.
    func allItemIDs(in catalogueID: PersistentIdentifier) throws -> [PersistentIdentifier] {
        let descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID && $0.deletedDate == nil },
            sortBy: [SortDescriptor(\.createdDate, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map(\.persistentModelID)
    }

    /// A CSV in a fresh temporary directory, UTF-8 with a byte order mark. The directory is
    /// removed again if the write fails or is cancelled.
    func writeCSV(_ request: SpreadsheetRequest, onProgress: Progress = { _, _ in }) throws -> URL {
        let catalogue = try catalogue(request)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(
            path: SpreadsheetEncoding.fileName(catalogueName: catalogue.name, filtered: request.filtered))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.write(contentsOf: Data(SpreadsheetEncoding.byteOrderMark.utf8))
            try stream(request, of: catalogue, as: .csv, onProgress: onProgress) { chunk in
                try handle.write(contentsOf: Data(chunk.utf8))
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return url
    }

    /// Tab-separated rows for the pasteboard.
    func tsv(_ request: SpreadsheetRequest, onProgress: Progress = { _, _ in }) throws -> String {
        var text = ""
        try stream(request, of: catalogue(request), as: .tsv, onProgress: onProgress) { text += $0 }
        return text
    }

    // MARK: Streaming

    private func catalogue(_ request: SpreadsheetRequest) throws -> Catalogue {
        guard let catalogue = modelContext.model(for: request.catalogueID) as? Catalogue else {
            throw WriterError.catalogueMissing
        }
        return catalogue
    }

    private func stream(
        _ request: SpreadsheetRequest,
        of catalogue: Catalogue,
        as format: SpreadsheetEncoding.RowFormat,
        onProgress: Progress,
        sink: (String) throws -> Void
    ) throws {
        let columns = SpreadsheetEncoding.columns(request.columns, in: catalogue.fieldDefinitions)
        let needsPhotoCount = columns.contains { if case .photoCount = $0 { true } else { false } }
        let style = request.options.valueStyle
        let total = request.itemIDs.count

        if request.options.includesHeader {
            try sink(SpreadsheetEncoding.row(SpreadsheetEncoding.headerCells(for: columns), as: format))
        }
        onProgress(0, total)

        for start in stride(from: 0, to: total, by: Self.batchSize) {
            try Task.checkCancellation()
            let ids = Array(request.itemIDs[start..<min(start + Self.batchSize, total)])
            var chunk = ""
            for item in try items(ids) {
                let photoCount = needsPhotoCount ? try photoCount(of: item) : 0
                let cells = SpreadsheetEncoding.cells(for: item, columns: columns, photoCount: photoCount, style: style)
                chunk += SpreadsheetEncoding.row(cells, as: format)
            }
            try sink(chunk)
            onProgress(start + ids.count, total)
        }
    }

    /// In `ids` order; an item deleted since the caller listed it is skipped.
    private func items(_ ids: [PersistentIdentifier]) throws -> [CatalogueItem] {
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: #Predicate { ids.contains($0.persistentModelID) })
        descriptor.relationshipKeyPathsForPrefetching = [\.storedFieldValues]
        let fetched = try modelContext.fetch(descriptor)
        let byID = Dictionary(fetched.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// A count query, so the photos' image data is never loaded.
    private func photoCount(of item: CatalogueItem) throws -> Int {
        let itemID = item.persistentModelID
        return try modelContext.fetchCount(FetchDescriptor<ItemPhoto>(
            predicate: #Predicate { $0.item?.persistentModelID == itemID }))
    }
}

// MARK: - Written Spreadsheet (Transferable)

/// A CSV already on disk, handed to the share sheet as the file itself.
struct WrittenSpreadsheetFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            SentTransferredFile(file.url, allowAccessingOriginalFile: false)
        }
        .suggestedFileName { $0.url.lastPathComponent }
    }
}

// MARK: - Catalogue CSV File (Transferable)

/// The whole catalogue, written when a share destination asks for it.
struct CatalogueCSVFile: Transferable, Sendable {
    let container: ModelContainer
    let catalogueID: PersistentIdentifier
    let columns: [ExportColumn]
    let filename: String

    @MainActor
    init(catalogue: Catalogue, container: ModelContainer, filename: String) {
        self.container = container
        catalogueID = catalogue.persistentModelID
        columns = ExportFormat.spreadsheet.columns(for: catalogue)
        self.filename = filename
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = try await Task.detached {
                let writer = SpreadsheetWriter(modelContainer: file.container)
                let ids = try await writer.allItemIDs(in: file.catalogueID)
                return try await writer.writeCSV(SpreadsheetRequest(
                    catalogueID: file.catalogueID, itemIDs: ids, columns: file.columns))
            }.value
            return SentTransferredFile(url, allowAccessingOriginalFile: false)
        }
        .suggestedFileName { $0.filename }
    }
}
