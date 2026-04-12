//
//  ContentView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Catalogue.priority) private var catalogues: [Catalogue]
    @State private var showingAddCatalogue = false
    @State private var showingImporter = false
    @State private var importErrorMessage: String?
    @State private var importProgress: (current: Int, total: Int)?
    @State private var selectedCatalogue: Catalogue?
    @State private var selectedItem: CatalogueItem?
    @State private var catalogueToEdit: Catalogue?
    @State private var catalogueToDelete: Catalogue?

#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } content: {
            if let catalogue = selectedCatalogue {
                CatalogueDetailView(catalogue: catalogue, selectedItem: $selectedItem)
            } else {
                ContentUnavailableView("Select a catalogue", systemImage: "square.grid.2x2")
            }
        } detail: {
#if os(macOS)
            if let catalogue = selectedCatalogue, let item = selectedItem {
                ItemDetailView(catalogue: catalogue, item: item, selectedItem: $selectedItem)
            } else {
                ContentUnavailableView("Select an item", systemImage: "cube")
            }
#else
            if horizontalSizeClass != .compact, let catalogue = selectedCatalogue, let item = selectedItem {
                ItemDetailView(catalogue: catalogue, item: item, selectedItem: $selectedItem)
            } else {
                ContentUnavailableView("Select an item", systemImage: "cube")
            }
#endif
        }
        .overlay {
            if let progress = importProgress {
                ImportProgressOverlay(current: progress.current, total: progress.total)
            }
        }
        .onChange(of: selectedCatalogue) {
            selectedItem = nil
        }
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert(
            "Delete \"\(catalogueToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { catalogueToDelete != nil },
                set: { if !$0 { catalogueToDelete = nil } }
            )
        ) {
            Button("Delete Catalogue", role: .destructive) {
                if let catalogue = catalogueToDelete {
                    // Nil out state before deleting: modelContext.delete() immediately
                    // invalidates the model, and SwiftUI can re-evaluate the alert
                    // message (which accesses catalogue.items) before the nil update lands.
                    catalogueToDelete = nil
                    modelContext.delete(catalogue)
                }
            }
            Button("Cancel", role: .cancel) { catalogueToDelete = nil }
        } message: {
            if let catalogue = catalogueToDelete {
                let activeCount = catalogue.items.count(where: { $0.deletedDate == nil })
                let deletedCount = catalogue.items.count(where: { $0.deletedDate != nil })
                if activeCount > 0 && deletedCount > 0 {
                    Text("This catalogue contains \(activeCount) item(s) and \(deletedCount) recently deleted item(s). All data will be permanently removed.")
                } else if activeCount > 0 {
                    Text("This catalogue contains \(activeCount) item(s). All data will be permanently removed.")
                } else {
                    Text("This catalogue has \(deletedCount) recently deleted item(s). All data will be permanently removed.")
                }
            }
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selectedCatalogue) {
            ForEach(catalogues) { catalogue in
                catalogueRow(catalogue)
            }
            .onMove(perform: moveCatalogues)
        }
        .navigationTitle("My Catalogues")
        .overlay {
            if catalogues.isEmpty {
                ContentUnavailableView(
                    "No Catalogues",
                    systemImage: "square.grid.2x2",
                    description: Text("Create your first catalogue to start organizing your collections")
                )
            }
        }
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
#endif
#if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Load Test Data", systemImage: "hammer") {
                    ForEach(TestDataGenerator.TestDataset.allCases, id: \.self) { dataset in
                        Button(dataset.displayName) {
                            seedTestData(dataset)
                        }
                    }
                }
            }
#endif
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import Catalogue", systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Catalogue", systemImage: "plus") {
                    showingAddCatalogue = true
                }
            }
        }
        .sheet(isPresented: $showingAddCatalogue) {
            AddEditCatalogueView(nextPriority: catalogues.count)
        }
        .sheet(item: $catalogueToEdit) { catalogue in
            AddEditCatalogueView(catalogue: catalogue, nextPriority: catalogues.count)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
    }

    @ViewBuilder
    private func catalogueRow(_ catalogue: Catalogue) -> some View {
        NavigationLink(value: catalogue) {
            CatalogueRow(catalogue: catalogue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                catalogueToEdit = catalogue
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                if selectedCatalogue == catalogue {
                    selectedCatalogue = nil
                }
                deleteCatalogue(catalogue)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                catalogueToEdit = catalogue
            } label: {
                Label("Edit Catalogue", systemImage: "pencil")
            }

            Button(role: .destructive) {
                if selectedCatalogue == catalogue {
                    selectedCatalogue = nil
                }
                deleteCatalogue(catalogue)
            } label: {
                Label("Delete Catalogue", systemImage: "trash")
            }
        }
    }

#if DEBUG
    private func seedTestData(_ dataset: TestDataGenerator.TestDataset) {
        Task { @MainActor in
            importProgress = (current: 0, total: 0)
            let catalogue = TestDataGenerator.seed(
                into: modelContext,
                dataset: dataset,
                priorityOffset: catalogues.count,
                onProgress: { current, total in
                    importProgress = (current: current, total: total)
                }
            )
            try? modelContext.save()
            importProgress = nil
            selectedCatalogue = catalogue
        }
    }
#endif

    private func handleImport(result: Result<[URL], Error>) {
        Task { @MainActor in
            do {
                guard let url = try result.get().first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                importProgress = (current: 0, total: 0)
                let imported = try CatalogueImporter.importCatalogues(
                    from: data,
                    into: modelContext,
                    priorityOffset: catalogues.count,
                    onProgress: { current, total in
                        importProgress = (current: current, total: total)
                    }
                )
                // Save immediately to assign permanent PersistentIdentifiers before
                // any view renders the imported models. Temporary IDs handed to views
                // before the save would crash if autosave fires while a view holds them.
                try? modelContext.save()
                importProgress = nil
                selectedCatalogue = imported.first
            } catch {
                importProgress = nil
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteCatalogue(_ catalogue: Catalogue) {
        let hasItems = catalogue.items.contains { $0.deletedDate == nil }
        let hasRecentlyDeleted = catalogue.items.contains { $0.deletedDate != nil }
        if hasItems || hasRecentlyDeleted {
            catalogueToDelete = catalogue
        } else {
            modelContext.delete(catalogue)
        }
    }

    private func moveCatalogues(from source: IndexSet, to destination: Int) {
        var reordered = catalogues
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, catalogue) in reordered.enumerated() {
            catalogue.priority = index
        }
    }
}

// MARK: - Import Progress Overlay

private struct ImportProgressOverlay: View {
    let current: Int
    let total: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if total > 0 {
                    ProgressView(value: Double(current), total: Double(total))
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                    Text("Processing \(current) of \(total) items…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Preparing import…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Catalogue.self, inMemory: true)
}
