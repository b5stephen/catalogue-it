//
//  ImportRequest.swift
//  catalogue-it
//

import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Import Request

/// What starts an import: the file picker, the clipboard, or something dropped. Handled by
/// `CatalogueImportFlow`, which `ContentView` hosts.
struct ImportRequest: Identifiable {
    enum Source {
        case file
        case paste
        case dropped(ImportDrop)
    }

    let id = UUID()
    let source: Source
    /// Where the destination picker starts; the user can still choose another. `nil` starts on
    /// a new catalogue.
    var suggestedDestination: ImportDestination?
}

// MARK: - Import Action

/// Starts an import from anywhere below `ContentView`, or from the menu bar.
struct ImportAction {
    let start: (ImportRequest) -> Void

    func callAsFunction(_ source: ImportRequest.Source, into destination: ImportDestination? = nil) {
        start(ImportRequest(source: source, suggestedDestination: destination))
    }
}

extension EnvironmentValues {
    @Entry var importAction = ImportAction { _ in }
}

extension FocusedValues {
    @Entry var importAction: ImportAction?
}

// MARK: - Import Drop

/// A file or text dropped onto a catalogue. Files are read as they arrive: the system removes
/// its copy once the drop handler returns.
nonisolated struct ImportDrop: Transferable {
    let data: Data
    let name: String
    let isDataFile: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .json) { received in
            try ImportDrop(file: received.file, isDataFile: true)
        }
        FileRepresentation(importedContentType: .excelWorkbook) { received in
            try ImportDrop(file: received.file, isDataFile: false)
        }
        FileRepresentation(importedContentType: .legacyExcelWorkbook) { received in
            try ImportDrop(file: received.file, isDataFile: false)
        }
        FileRepresentation(importedContentType: .commaSeparatedText) { received in
            try ImportDrop(file: received.file, isDataFile: false)
        }
        FileRepresentation(importedContentType: .tabSeparatedText) { received in
            try ImportDrop(file: received.file, isDataFile: false)
        }
        FileRepresentation(importedContentType: .plainText) { received in
            try ImportDrop(file: received.file, isDataFile: false)
        }
        ProxyRepresentation(importing: { (text: String) in
            ImportDrop(data: Data(text.utf8), name: String(localized: "Dropped Items"), isDataFile: false)
        })
    }

    init(data: Data, name: String, isDataFile: Bool) {
        self.data = data
        self.name = name
        self.isDataFile = isDataFile
    }

    private init(file: URL, isDataFile: Bool) throws {
        let isScoped = file.startAccessingSecurityScopedResource()
        defer { if isScoped { file.stopAccessingSecurityScopedResource() } }
        self.init(data: try Data(contentsOf: file), name: file.deletingPathExtension().lastPathComponent, isDataFile: isDataFile)
    }
}

// MARK: - Content Types

extension UTType {
    // Declared by the system; `UTType` has no constants for them.
    nonisolated static let excelWorkbook = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .spreadsheet
    nonisolated static let legacyExcelWorkbook = UTType("com.microsoft.excel.xls") ?? .spreadsheet
}

// MARK: - Drop Target

extension View {
    /// Accepts a Data file, Excel workbook, spreadsheet or text dropped here, importing into `destination`.
    func importDropTarget(into destination: ImportDestination?, isTargeted: Binding<Bool>? = nil) -> some View {
        modifier(ImportDropTarget(destination: destination, isTargeted: isTargeted))
    }
}

private struct ImportDropTarget: ViewModifier {
    let destination: ImportDestination?
    let isTargeted: Binding<Bool>?
    @Environment(\.importAction) private var importAction

    func body(content: Content) -> some View {
        content.dropDestination(for: ImportDrop.self) { drops, _ in
            guard let drop = drops.first else { return false }
            importAction(.dropped(drop), into: destination)
            return true
        } isTargeted: { targeted in
            isTargeted?.wrappedValue = targeted
        }
    }
}
