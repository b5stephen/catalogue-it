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
    @State private var isBeta = false
    @State private var importErrorMessage: String?
    @State private var importProgress: (current: Int, total: Int)?
#if os(macOS)
    @State private var selectedCatalogue: Catalogue?
#else
    /// The leading column's stack: empty on the catalogue list, one catalogue on its items.
    /// `selectedCatalogue` is derived from it so import, seeding and deletion write one piece
    /// of state on every platform. Popping the stack clears the selection, which in turn
    /// clears `selectedItem` via `onChange`.
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
    /// Read here, outside the split view, so it reflects the window and not a column.
    private var hasDetailColumn: Bool { horizontalSizeClass != .compact }
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    /// The detail column's wash keeps clear of the leading column only while it is showing.
    private var detailWashEdges: Edge.Set {
        columnVisibility == .detailOnly ? .all : CatalogueWash.detailColumnEdges
    }
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
        // Going back to the catalogue list (nil) keeps the open item in the detail column: the
        // list is a step away, not a different place, and losing the item on every Back was
        // jarring. Entering a catalogue clears it unless it's the item's own, so stepping back
        // into the same catalogue finds it still selected.
        .onChange(of: selectedCatalogue) { _, catalogue in
            if let catalogue, catalogue != selectedItem?.catalogue {
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
    /// Catalogues | items | item detail. The Mac has the width for all three, and the sidebar
    /// selection is what keyboard navigation and the standard sidebar look are built on.
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
    /// Two columns, with the items screen pushed onto a stack *inside* the leading column.
    ///
    /// Three columns don't work on iPad in portrait: the only resting state is items + detail
    /// with the sidebar hidden, so a fresh launch with nothing selected shows two empty
    /// placeholders, and every attempt to force the sidebar open with a `columnVisibility`
    /// binding was overwritten during the split view's first layout pass. With two columns and
    /// `.balanced`, the leading column is always tiled, and it shows either the catalogue list
    /// or — a Back tap away — the items of the chosen one. In compact width the whole thing
    /// collapses to catalogues → items → item detail on this one explicit stack, which also
    /// sidesteps the split view's own re-hosting of pushed columns.
    private var twoColumnLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationStack(path: $cataloguePath) {
                sidebarContent
                    .navigationDestination(for: Catalogue.self) { catalogue in
                        CatalogueDetailView(catalogue: catalogue, selectedItem: $selectedItem)
                            // On the destination itself: set on the stack, it never reached
                            // the pushed view once the split view had collapsed on iPhone.
                            .environment(\.hasDetailColumn, hasDetailColumn)
                    }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 420, max: 560)
        } detail: {
            // The item's own catalogue, not the selected one: the item outlives the pop back
            // to the catalogue list, where nothing is selected.
            if hasDetailColumn, let item = selectedItem, let catalogue = item.catalogue {
                ItemDetailView(catalogue: catalogue, item: item, selectedItem: $selectedItem)
                    .environment(\.catalogueWashEdges, detailWashEdges)
            } else {
                selectAnItemPlaceholder
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
#endif

    /// The empty detail column. Inside a catalogue it sits on that catalogue's wash, so the
    /// two columns read as one place rather than the detail side dropping back to plain grey.
    @ViewBuilder
    private var selectAnItemPlaceholder: some View {
        let placeholder = ContentUnavailableView("Select an item", systemImage: "cube")
        if let catalogue = selectedCatalogue {
            placeholder.background(CatalogueWash(catalogue: catalogue, edges: detailWashEdges, glow: true))
        } else {
            placeholder
        }
    }

    /// Where the catalogue list's seldom-used actions go: the overflow menu on iOS, the bar on
    /// macOS, which has the room and no overflow to speak of.
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
            if isBeta {
                ToolbarItem(placement: rareActionPlacement) {
                    Button("Sync Diagnostics", systemImage: "stethoscope") {
                        showingSyncDiagnostics = true
                    }
                }
            }
#endif
            // Import is rare, so on iOS it goes behind the overflow menu: the leading column
            // is ~300pt on an iPad in portrait, and a title plus three or four trailing
            // buttons don't fit — the bar drops the title rather than a button.
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
            AddEditCatalogueView(nextPriority: catalogues.count)
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

    /// Deletes outright when there is nothing in the catalogue, otherwise asks first.
    private func requestDelete(_ catalogue: Catalogue) {
        let hasItems = catalogue.items.contains { $0.deletedDate == nil }
        let hasRecentlyDeleted = catalogue.items.contains { $0.deletedDate != nil }
        if hasItems || hasRecentlyDeleted {
            catalogueToDelete = catalogue
        } else {
            delete(catalogue)
        }
    }

    /// Clears the selection first so no column is left showing a catalogue that is about to
    /// vanish, then hands the teardown to the background actor.
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
