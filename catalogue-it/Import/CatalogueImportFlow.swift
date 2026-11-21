//
//  CatalogueImportFlow.swift
//  catalogue-it
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Catalogue Import Flow

/// The import flow: file picker or pasted rows, the destination or column-mapping sheet,
/// progress, then the result. A Data file holding one catalogue asks where it goes when there
/// are catalogues to import into; a Data file with several is imported as new catalogues
/// straight away. Anything else is read as a spreadsheet.
struct CatalogueImportFlow: ViewModifier {
    @Binding var isPickingFile: Bool
    /// Set to read the clipboard as spreadsheet rows; set back once read.
    @Binding var isPasting: Bool
    let catalogues: [Catalogue]
    /// The new catalogue, or the one imported into, to select.
    let onImported: (Catalogue) -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var pendingFile: PendingFile?
    @State private var pendingTable: PendingTable?
    @State private var progress: (done: Int, total: Int)?
    @State private var errorMessage: String?
    @State private var completed: CompletedImport?
    @State private var confirmedImport: ConfirmedImport?

    struct PendingFile: Identifiable {
        let id = UUID()
        let file: CatalogueExportFile
    }

    struct PendingTable: Identifiable {
        let id = UUID()
        let table: ImportTable
        let sourceName: String
    }

    struct ConfirmedImport {
        let file: CatalogueExportFile
        let destination: ImportDestination
        let skippingDuplicates: Bool
        /// Off for a spreadsheet, whose columns the user mapped to fields one by one.
        var matchingFieldsByName = true
    }

    enum Source {
        case dataFile(CatalogueExportFile)
        case table(ImportTable)
    }

    struct CompletedImport {
        let catalogue: Catalogue
        let summary: ImportSummary
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let progress {
                    ProgressOverlay(current: progress.done, total: progress.total, preparingText: "Preparing import…")
                }
            }
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: [.json, .commaSeparatedText, .tabSeparatedText, .delimitedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                open(result)
            }
            .onChange(of: isPasting) {
                guard isPasting else { return }
                isPasting = false
                paste()
            }
            // Started from onDismiss: an import that finishes while the sheet is still closing
            // loses its result alert.
            .sheet(item: $pendingFile, onDismiss: startConfirmedImport) { pending in
                if let catalogue = pending.file.catalogues.first {
                    ImportDestinationSheet(file: catalogue, catalogues: catalogues) { destination, skippingDuplicates in
                        confirmedImport = ConfirmedImport(
                            file: pending.file, destination: destination, skippingDuplicates: skippingDuplicates)
                    }
                }
            }
            .sheet(item: $pendingTable, onDismiss: startConfirmedImport) { pending in
                TableImportSheet(table: pending.table, sourceName: pending.sourceName, catalogues: catalogues) { catalogue, destination in
                    confirmedImport = ConfirmedImport(
                        file: CatalogueExportFile(exportedAt: .now, catalogues: [catalogue]),
                        destination: destination,
                        skippingDuplicates: false,
                        matchingFieldsByName: false)
                }
            }
            .alert(
                "Import Failed",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                "Import Complete",
                isPresented: Binding(get: { completed != nil }, set: { if !$0 { completed = nil } }),
                presenting: completed
            ) { done in
                if !done.summary.insertedItemIDs.isEmpty {
                    Button("Undo Import", role: .destructive) {
                        undo(done.summary)
                        onImported(done.catalogue)
                    }
                }
                Button("OK", role: .cancel) { onImported(done.catalogue) }
            } message: { done in
                Text(Self.message(for: done))
            }
    }

    // MARK: Steps

    private func open(_ result: Result<[URL], Error>) {
        Task {
            do {
                guard let url = try result.get().first else { return }
                progress = (done: 0, total: 0)
                switch try await Task.detached(operation: { try Self.read(url) }).value {
                case .dataFile(let file) where file.catalogues.count == 1 && !catalogues.isEmpty:
                    progress = nil
                    pendingFile = PendingFile(file: file)
                case .dataFile(let file):
                    await run(ConfirmedImport(file: file, destination: .newCatalogue, skippingDuplicates: false))
                case .table(let table):
                    progress = nil
                    pendingTable = PendingTable(table: table, sourceName: url.deletingPathExtension().lastPathComponent)
                }
            } catch {
                progress = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startConfirmedImport() {
        guard let confirmed = confirmedImport else { return }
        confirmedImport = nil
        Task { await run(confirmed) }
    }

    /// A Data file is JSON, whatever its name; everything else is read as a spreadsheet.
    nonisolated private static func read(_ url: URL) throws -> Source {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let firstByte = data.first { !(Character(UnicodeScalar($0)).isWhitespace) }
        if url.pathExtension.lowercased() == "json" || firstByte == UInt8(ascii: "{") {
            return .dataFile(try CatalogueImporter.decode(data))
        }
        return .table(try DelimitedTextParser.parse(data))
    }

    private func paste() {
#if os(macOS)
        let text = NSPasteboard.general.string(forType: .string)
#else
        let text = UIPasteboard.general.string
#endif
        guard let text, let table = try? DelimitedTextParser.parse(text) else {
            errorMessage = String(localized: "Copy some rows from a spreadsheet first, then paste them here.")
            return
        }
        pendingTable = PendingTable(table: table, sourceName: String(localized: "Pasted Items"))
    }

    private func run(_ confirmed: ConfirmedImport) async {
        let file = confirmed.file
        let destination = confirmed.destination
        let skippingDuplicates = confirmed.skippingDuplicates
        let matchingFieldsByName = confirmed.matchingFieldsByName
        let container = modelContext.container
        let priorityOffset = catalogues.count
        progress = (done: 0, total: 0)

        let (updates, continuation) = AsyncStream.makeStream(of: (Int, Int).self, bufferingPolicy: .bufferingNewest(1))
        let watcher = Task {
            for await (done, total) in updates { progress = (done: done, total: total) }
        }
        let result = await Task.detached { () throws -> ImportSummary in
            let importer = ItemImporter(modelContainer: container)
            let report: ItemImporter.Progress = { done, total in continuation.yield((done, total)) }
            switch destination {
            case .newCatalogue:
                return try await importer.importAsNewCatalogues(file, priorityOffset: priorityOffset, onProgress: report)
            case .existing(let catalogueID):
                guard let catalogue = file.catalogues.first else { return ImportSummary() }
                return try await importer.importCatalogue(
                    catalogue, into: catalogueID, skippingDuplicates: skippingDuplicates,
                    matchingFieldsByName: matchingFieldsByName, onProgress: report)
            }
        }.result
        continuation.finish()
        watcher.cancel()
        progress = nil

        switch result {
        case .success(let summary):
            guard let first = summary.catalogueIDs.first.flatMap({ modelContext.model(for: $0) as? Catalogue }) else { return }
            // The catalogue opens once the alert is answered: a navigation push alongside it
            // stops the alert appearing.
            if case .existing = destination {
                completed = CompletedImport(catalogue: first, summary: summary)
            } else {
                onImported(first)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Moves the imported items to Recently Deleted. Fields and options the import added stay.
    private func undo(_ summary: ImportSummary) {
        let container = modelContext.container
        let ids = summary.insertedItemIDs
        Task {
            progress = (done: 0, total: 0)
            let result = await Task.detached {
                try await ItemTrashActor(modelContainer: container).setDeletedDate(.now, for: ids)
            }.result
            progress = nil
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func message(for done: CompletedImport) -> String {
        let summary = done.summary
        var lines = [inflected("Added ^[\(summary.insertedItemIDs.count) item](inflect: true) to “\(done.catalogue.name)”.")]
        if summary.skippedDuplicateCount > 0 {
            lines.append(inflected("Skipped ^[\(summary.skippedDuplicateCount) item](inflect: true) already there."))
        }
        if summary.addedFieldCount > 0 {
            lines.append(inflected("Added ^[\(summary.addedFieldCount) new field](inflect: true)."))
        }
        if summary.addedOptionCount > 0 {
            lines.append(inflected("Added ^[\(summary.addedOptionCount) new option](inflect: true)."))
        }
        return lines.joined(separator: " ")
    }

    /// Alert messages are plain strings, so the inflection is applied here.
    private static func inflected(_ resource: LocalizedStringResource) -> String {
        String(AttributedString(localized: resource).characters)
    }
}
