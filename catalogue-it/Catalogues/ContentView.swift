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
    // Catalogues marked for deletion vanish from the sidebar instantly, while
    // BackgroundDeletionActor tears their data down off the main thread.
    @Query(filter: #Predicate<Catalogue> { !$0.pendingDeletion }, sort: \Catalogue.priority)
    private var catalogues: [Catalogue]
    @State private var showingAddCatalogue = false
    @State private var showingImporter = false
    @State private var showingSyncDiagnostics = false
    @State private var importErrorMessage: String?
    @State private var importProgress: (current: Int, total: Int)?
    @State private var selectedCatalogue: Catalogue?
    @State private var selectedItem: CatalogueItem?
    @State private var catalogueToEdit: Catalogue?
    @State private var catalogueToDelete: Catalogue?
#if DEBUG
    @State private var showingSeedSheet = false
    @State private var showingSchemaResult = false
    @State private var schemaResult = ""
    @State private var sortKeyRecalcProgress: (current: Int, total: Int)?
#endif

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
                ProgressOverlay(
                    current: progress.current,
                    total: progress.total,
                    preparingText: "Preparing import…"
                )
            }
#if DEBUG
            if let progress = sortKeyRecalcProgress {
                ProgressOverlay(
                    current: progress.current,
                    total: progress.total,
                    preparingText: "Recalculating sort keys…",
                    processingText: { current, total in "Recalculating \(current) of \(total) items…" }
                )
            }
#endif
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
                    catalogueToDelete = nil
                    if selectedCatalogue == catalogue {
                        selectedCatalogue = nil
                    }
                    DeletionService.markForBackgroundDeletion(catalogue, in: modelContext)
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
#if !os(macOS)
        // Cards, not a tied-together list: a plain list plus clear row backgrounds hands the
        // whole row rect to `CatalogueCardView`, while the list keeps swipe actions, drag
        // reordering and selection. `listRowSpacing` (rather than vertical row insets) puts the
        // gap *between* rows, so the swipe buttons stay flush with the card edges.
        .listStyle(.plain)
        .listRowSpacing(AppConstants.CatalogueCard.rowSpacing)
        .contentMargins(.vertical, AppConstants.CatalogueCard.rowSpacing, for: .scrollContent)
#endif
        .navigationTitle("My Catalogues")
        .cloudSyncStatusBar()
        .overlay {
            if catalogues.isEmpty {
                // While the first import is still running, "No Catalogues" is actively
                // misleading — it's the moment a user is most likely to conclude sync is
                // broken, or start recreating catalogues they already have.
                if case .syncing = CloudKitSyncMonitor.shared.status {
                    ContentUnavailableView {
                        Label("Syncing from iCloud", systemImage: "icloud.and.arrow.down")
                    } description: {
                        Text("Your catalogues will appear here in a moment.")
                    }
                } else {
                    ContentUnavailableView(
                        "No Catalogues",
                        systemImage: "square.grid.2x2",
                        description: Text("Create your first catalogue to start organizing your collections")
                    )
                }
            }
        }

#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
#endif
        .toolbar {
#if DEBUG
            DebugToolbarItem(
                onLoadTestData: { showingSeedSheet = true },
                onRecalculateSortKeys: { recalculateAllSortKeys() },
                onValidateCloudKitSchema: { runSchemaInitializer(dryRun: true) },
                onInitializeCloudKitSchema: { runSchemaInitializer(dryRun: false) },
                onShowSyncDiagnostics: { showingSyncDiagnostics = true }
            )
#else
            // TestFlight gets its own toolbar button, since the hammer menu that holds this in
            // DEBUG builds doesn't exist here — and a silent failure shows no status bar, so
            // the sheet needs a way in that doesn't depend on one being on screen. Release
            // builds from the App Store show nothing.
            if BuildEnvironment.isBeta {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sync Diagnostics", systemImage: "stethoscope") {
                        showingSyncDiagnostics = true
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
        .sheet(isPresented: $showingSyncDiagnostics) {
            SyncDiagnosticsView()
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
#if DEBUG
        .alert("CloudKit Schema", isPresented: $showingSchemaResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(schemaResult)
        }
        .sheet(isPresented: $showingSeedSheet) {
            SeedDataSheet { itemCount, includesPhotos, catalogueName in
                seedTestData(itemCount: itemCount, includesPhotos: includesPhotos, catalogueName: catalogueName)
            }
        }
#endif
    }

    /// Navigation is driven by the list's selection rather than a `NavigationLink`: a link
    /// draws a disclosure chevron that has nowhere sensible to sit on a card. The split view
    /// pushes the catalogue's items from the selection alone, in compact width as well as
    /// regular, so the `tag` below is what makes a row selectable.
    @ViewBuilder
    private func catalogueRow(_ catalogue: Catalogue) -> some View {
        Group {
#if os(macOS)
            CatalogueRow(catalogue: catalogue)
#else
            CatalogueCardView(catalogue: catalogue, isSelected: selectedCatalogue == catalogue)
#endif
        }
        .tag(catalogue)
#if !os(macOS)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(
            EdgeInsets(
                top: 0,
                leading: AppConstants.CatalogueCard.horizontalInset,
                bottom: 0,
                trailing: AppConstants.CatalogueCard.horizontalInset
            )
        )
#endif
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
#if os(macOS)
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
#endif
    }

#if DEBUG
    private func seedTestData(itemCount: Int, includesPhotos: Bool, catalogueName: String) {
        Task { @MainActor in
            importProgress = (current: 0, total: 0)
            let catalogue = await TestDataGenerator.seed(
                into: modelContext,
                catalogueName: catalogueName,
                itemCount: itemCount,
                includesPhotos: includesPhotos,
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

    /// Recomputes `FieldValue.tiebreakKey` across every catalogue — a dev-only escape hatch
    /// for refreshing sort order after changes to the tiebreak encoding itself, since the app
    /// hasn't shipped yet and there's no real user data to migrate. Shows progress immediately
    /// (no delay) since this is an explicit, deliberate action rather than an incidental one.
    private func recalculateAllSortKeys() {
        Task { @MainActor in
            sortKeyRecalcProgress = (current: 0, total: 0)
            let totalItems = catalogues.reduce(0) { $0 + $1.items.count { $0.deletedDate == nil } }
            var completedBefore = 0
            for catalogue in catalogues {
                await CatalogueSortKeyMaintenance.recomputeTiebreakKeys(
                    for: catalogue,
                    in: modelContext,
                    onProgress: { current, _ in
                        sortKeyRecalcProgress = (current: completedBefore + current, total: totalItems)
                    }
                )
                completedBefore += catalogue.items.count { $0.deletedDate == nil }
            }
            sortKeyRecalcProgress = nil
        }
    }

    /// Pushes the full CloudKit schema to the Development environment, or with `dryRun` just
    /// validates it and prints it to the console. See `CloudKitSchemaInitializer` for why the
    /// schema does not create itself correctly from ordinary use of the app.
    ///
    /// Detached: `initializeCloudKitSchema` is synchronous and talks to the network, so running
    /// it on the main actor would freeze the UI for its duration.
    private func runSchemaInitializer(dryRun: Bool) {
        Task {
            let result = await Task.detached {
                do { return try await CloudKitSchemaInitializer.run(dryRun: dryRun) }
                catch { return "Failed: \(error.localizedDescription)" }
            }.value
            schemaResult = result
            showingSchemaResult = true
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
                let imported = try await CatalogueImporter.importCatalogues(
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
            DeletionService.markForBackgroundDeletion(catalogue, in: modelContext)
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

#Preview {
    ContentView()
        .modelContainer(for: Catalogue.self, inMemory: true)
}
