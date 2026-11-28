//
//  CatalogueEmptyStateView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

// MARK: - Empty State View

struct CatalogueEmptyStateView: View {
    let catalogue: Catalogue
    let statusTab: StatusTab
    let hasActiveFlags: Bool
    let isFiltered: Bool
    let onAddItem: () -> Void

    @Environment(\.importAction) private var importAction

    /// A real status, not "All", so the copy can name it.
    private var selectedStatusDescriptor: StatusTabDescriptor? {
        guard statusTab != .all else { return nil }
        return catalogue.statusTabDescriptors.first { $0.tab == statusTab }
    }

    var body: some View {
        if isFiltered {
            ContentUnavailableView.search
        } else if hasActiveFlags {
            // The catalogue may be full, just not of flagged items.
            ContentUnavailableView(
                "No Matching Items",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No items match the filters you've turned on.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let descriptor = selectedStatusDescriptor {
            ContentUnavailableView {
                Label("Nothing in \(descriptor.label) Yet", systemImage: descriptor.systemImage)
            } description: {
                Text("Items set to \(descriptor.label) appear here.")
            } actions: {
                addItemButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Add Your First Item", systemImage: "tray.2")
            } description: {
                Text("Fill in its fields and add photos, or bring in a spreadsheet of what you already have.")
            } actions: {
                addItemButton
                ImportMenu { source in
                    importAction(source, into: .existing(catalogue.persistentModelID))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var addItemButton: some View {
        Button("Add Item", systemImage: "plus", action: onAddItem)
            .buttonStyle(.borderedProminent)
    }
}

// MARK: - Welcome View

/// What a fresh install shows in place of the catalogue list.
struct WelcomeEmptyStateView: View {
    let onNewCatalogue: () -> Void
    let onImport: (ImportRequest.Source) -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Start Your First Catalogue", systemImage: "books.vertical")
        } description: {
            Text("Keep track of anything you collect, from stamps and books to model planes, with your own fields and photos.")
        } actions: {
            Button("New Catalogue", systemImage: "plus", action: onNewCatalogue)
                .buttonStyle(.borderedProminent)
            ImportMenu(onImport: onImport)
        }
    }
}

// MARK: - Import Menu

/// The secondary action under an empty state's primary button.
private struct ImportMenu: View {
    let onImport: (ImportRequest.Source) -> Void

    var body: some View {
        Menu("Import from a Spreadsheet", systemImage: "square.and.arrow.down") {
            Button("Import from File…", systemImage: "doc") { onImport(.file) }
            Button("Paste from Spreadsheet", systemImage: "tablecells") { onImport(.paste) }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
#if os(macOS)
        .fixedSize()
#endif
    }
}

#Preview("Welcome") {
    NavigationStack {
        WelcomeEmptyStateView(onNewCatalogue: {}, onImport: { _ in })
            .navigationTitle("Catalogues")
    }
}
