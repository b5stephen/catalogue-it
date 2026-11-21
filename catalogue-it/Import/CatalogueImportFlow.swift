//
//  CatalogueImportFlow.swift
//  catalogue-it
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Catalogue Import Flow

/// The Import Catalogue flow: file picker, destination sheet, progress, then the result. A file
/// holding one catalogue asks where it goes when there are catalogues to import into; anything
/// else is imported as new catalogues straight away.
struct CatalogueImportFlow: ViewModifier {
    @Binding var isPickingFile: Bool
    let catalogues: [Catalogue]
    /// The new catalogue, or the one imported into, to select.
    let onImported: (Catalogue) -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var pendingFile: PendingFile?
    @State private var progress: (done: Int, total: Int)?
    @State private var errorMessage: String?
    @State private var completed: CompletedImport?
    @State private var confirmedImport: ConfirmedImport?

    struct PendingFile: Identifiable {
        let id = UUID()
        let file: CatalogueExportFile
    }

    struct ConfirmedImport {
        let file: CatalogueExportFile
        let destination: ImportDestination
        let skippingDuplicates: Bool
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
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                open(result)
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
                let file = try await Task.detached { try Self.read(url) }.value
                if file.catalogues.count == 1 && !catalogues.isEmpty {
                    progress = nil
                    pendingFile = PendingFile(file: file)
                } else {
                    await run(file, to: .newCatalogue, skippingDuplicates: false)
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
        Task { await run(confirmed.file, to: confirmed.destination, skippingDuplicates: confirmed.skippingDuplicates) }
    }

    nonisolated private static func read(_ url: URL) throws -> CatalogueExportFile {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        return try CatalogueImporter.decode(Data(contentsOf: url))
    }

    private func run(_ file: CatalogueExportFile, to destination: ImportDestination, skippingDuplicates: Bool) async {
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
                    catalogue, into: catalogueID, skippingDuplicates: skippingDuplicates, onProgress: report)
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
        var lines = [String(localized: "Added \(summary.insertedItemIDs.count) items to “\(done.catalogue.name)”.")]
        if summary.skippedDuplicateCount > 0 {
            lines.append(String(localized: "Skipped \(summary.skippedDuplicateCount) items already there."))
        }
        if summary.addedFieldCount > 0 {
            lines.append(String(localized: "Added \(summary.addedFieldCount) new fields."))
        }
        if summary.addedOptionCount > 0 {
            lines.append(String(localized: "Added \(summary.addedOptionCount) new options."))
        }
        return lines.joined(separator: " ")
    }
}
