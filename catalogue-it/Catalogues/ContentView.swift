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
    // Pending deletion hides a catalogue at once; BackgroundDeletionActor does the teardown.
    @Query(filter: #Predicate<Catalogue> { !$0.pendingDeletion }, sort: \Catalogue.priority)
    private var catalogues: [Catalogue]
    @State private var showingAddCatalogue = false
    @State private var showingImporter = false
    @State private var showingSyncDiagnostics = false
    @State private var isBeta = false
    @State private var importErrorMessage: String?
    @State private var importProgress: (current: Int, total: Int)?
#if os(macOS)
    @State private var selectedCatalogue: Catalogue?
#else
    /// Empty on the catalogue list, one catalogue on its items. `selectedCatalogue` derives from
    /// it so every writer sets one piece of state.
    @State private var cataloguePath: [Catalogue] = []
    private var selectedCatalogue: Catalogue? {
        get { cataloguePath.last }
        nonmutating set { cataloguePath = newValue.map { [$0] } ?? [] }
    }
#endif
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
    /// Read outside the split view, so it reflects the window and not a column.
    private var hasDetailColumn: Bool { horizontalSizeClass != .compact }
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
#endif

    var body: some View {
        Group {
#if os(macOS)
            threeColumnLayout
#else
            twoColumnLayout
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
#if os(macOS)
        .onChange(of: selectedCatalogue) {
            selectedItem = nil
        }
#else
        // Back to the catalogue list keeps the open item: losing it on every Back was jarring.
        // Entering a catalogue clears it unless it's the item's own.
        .onChange(of: selectedCatalogue) { _, catalogue in
            if let catalogue, catalogue != selectedItem?.catalogue {
                selectedItem = nil
            }
        }
        // In one column a selected item is pushed the moment its catalogue opens, so one kept for
        // the detail column would jump straight past the catalogue.
        .onChange(of: hasDetailColumn) { _, hasDetailColumn in
            if !hasDetailColumn && cataloguePath.isEmpty {
                selectedItem = nil
            }
        }
#endif
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
                    delete(catalogue)
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

#if os(macOS)
    /// The Mac has the width for three columns, and sidebar selection carries its keyboard
    /// navigation and standard look.
    private var threeColumnLayout: some View {
        NavigationSplitView {
            sidebarContent
        } content: {
            if let catalogue = selectedCatalogue {
                CatalogueDetailView(catalogue: catalogue, selectedItem: $selectedItem)
            } else {
                ContentUnavailableView("Select a catalogue", systemImage: "square.grid.2x2")
            }
        } detail: {
            if let catalogue = selectedCatalogue, let item = selectedItem {
                ItemDetailView(catalogue: catalogue, item: item, selectedItem: $selectedItem)
            } else {
                selectAnItemPlaceholder
            }
        }
    }
#else
    /// Two columns, with the items pushed inside the leading one. Three don't work on iPad in
    /// portrait: the only resting state hides the sidebar, a fresh launch shows two empty
    /// placeholders, and the split view overwrites a forced `columnVisibility` on first layout.
    /// In compact width this collapses to one explicit stack, which also sidesteps the split
    /// view's re-hosting of pushed columns.
    private var twoColumnLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationStack(path: $cataloguePath) {
                sidebarContent
                    .navigationDestination(for: Catalogue.self) { catalogue in
                        CatalogueDetailView(catalogue: catalogue, selectedItem: $selectedItem)
                            // Set on the stack, it never reached the pushed view once the split view collapsed.
                            .environment(\.hasDetailColumn, hasDetailColumn)
                    }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 420, max: 560)
        } detail: {
            // The item's own catalogue: the item outlives the pop back to the catalogue list.
            if hasDetailColumn, let item = selectedItem, let catalogue = item.catalogue {
                ItemDetailView(catalogue: catalogue, item: item, selectedItem: $selectedItem)
            } else {
                selectAnItemPlaceholder
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
#endif

    /// On the catalogue's wash, so the detail side doesn't drop back to plain grey.
    @ViewBuilder
    private var selectAnItemPlaceholder: some View {
        let placeholder = ContentUnavailableView("Select an item", systemImage: "cube")
        if let catalogue = selectedCatalogue {
#if os(macOS)
            placeholder.catalogueGround(catalogue, glow: true, inSplitView: false)
#else
            placeholder.catalogueGround(catalogue, glow: true, inSplitView: true)
#endif
        } else {
            placeholder
        }
    }

    /// macOS has the room, and no overflow to speak of.
    private var rareActionPlacement: ToolbarItemPlacement {
#if os(macOS)
        .primaryAction
#else
        .secondaryAction
#endif
    }

    @ViewBuilder
    private var sidebarContent: some View {
        Group {
#if os(macOS)
            MacCatalogueSidebar(
                catalogues: catalogues,
                selectedCatalogue: $selectedCatalogue,
                onEdit: { catalogueToEdit = $0 },
                onDelete: { requestDelete($0) },
                onMove: moveCatalogues
            )
#else
            CatalogueSidebar(
                catalogues: catalogues,
                onEdit: { catalogueToEdit = $0 },
                onDelete: { requestDelete($0) },
                onMove: moveCatalogues
            )
#endif
        }
        .navigationTitle("Catalogues")
        .cloudSyncStatusBar()
        .overlay {
            if catalogues.isEmpty {
                // "No Catalogues" during the first import makes sync look broken.
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
            // The hammer menu that holds this is DEBUG-only, and a silent failure shows no status bar
            // to tap. App Store builds show nothing.
            if isBeta {
                ToolbarItem(placement: rareActionPlacement) {
                    Button("Sync Diagnostics", systemImage: "stethoscope") {
                        showingSyncDiagnostics = true
                    }
                }
            }
#endif
            // Rare, so behind the overflow: on an iPad in portrait the ~300pt bar would drop the title
            // rather than a button.
            ToolbarItem(placement: rareActionPlacement) {
                Button("Import Catalogue", systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Catalogue", systemImage: "plus") {
                    showingAddCatalogue = true
                }
            }
        }
        .sheet(isPresented: $showingAddCatalogue) {
            AddEditCatalogueView(
                nextPriority: catalogues.count,
                existingColorHexes: catalogues.map(\.colorHex)
            )
        }
        .sheet(isPresented: $showingSyncDiagnostics) {
            SyncDiagnosticsView()
        }
        .task { isBeta = await BuildEnvironment.isBeta() }
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

    /// Dev-only: refreshes sort order after a change to the tiebreak encoding.
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

    /// See `CloudKitSchemaInitializer` for why the schema can't come from ordinary use. Detached:
    /// `initializeCloudKitSchema` is synchronous and talks to the network.
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
                // Permanent identifiers before any view renders the imported models: a temporary one held
                // by a view crashes if autosave fires.
                try? modelContext.save()
                importProgress = nil
                selectedCatalogue = imported.first
            } catch {
                importProgress = nil
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func requestDelete(_ catalogue: Catalogue) {
        let hasItems = catalogue.items.contains { $0.deletedDate == nil }
        let hasRecentlyDeleted = catalogue.items.contains { $0.deletedDate != nil }
        if hasItems || hasRecentlyDeleted {
            catalogueToDelete = catalogue
        } else {
            delete(catalogue)
        }
    }

    /// Clears the selection first, so no column shows a catalogue about to vanish.
    private func delete(_ catalogue: Catalogue) {
        if selectedItem?.catalogue == catalogue {
            selectedItem = nil
        }
        if selectedCatalogue == catalogue {
            selectedCatalogue = nil
        }
        DeletionService.markForBackgroundDeletion(catalogue, in: modelContext)
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
