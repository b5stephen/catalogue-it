//
//  CatalogueDetailView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

// MARK: - Catalogue Detail View

struct CatalogueDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var catalogue: Catalogue
    @Binding var selectedItem: CatalogueItem?

    @Environment(\.colorScheme) private var colorScheme
#if !os(macOS)
    @Environment(\.hasDetailColumn) private var hasDetailColumn
#endif

    @State private var selectedTab: StatusTab = .all
    /// The catalogue `selectedTab` was seeded for. `.task` is cancelled and re-run whenever
    /// this view disappears and comes back — which includes pushing an item detail and
    /// popping it again in compact width — so seeding unconditionally there would throw the
    /// user's tab away every time they returned from an item. Seeding is therefore keyed on
    /// the catalogue itself: a different catalogue gets its default tab, the same one keeps
    /// whatever the user last chose.
    @State private var seededCatalogueID: PersistentIdentifier?
    /// `fieldID`s of the flag filters the user has switched on. ANDed with each other
    /// and with the status tab.
    @State private var activeFlagIDs: Set<UUID> = []
    @State private var showingEditCatalogue = false
    @State private var showingAddItem = false
    @State private var showingStats = false
    @State private var showingRecentlyDeleted = false
    @State private var searchText: String = ""
    @State private var appliedSearchText: String = ""
    @State private var displayedCount: Int = 0
    /// Whether the band's title row has collapsed, at which point the bar shows the name and
    /// count itself.
    @State private var isBandScrolledAway = false
    @State private var bandScroll = BandScrollState()
    /// The band's full height, which the list reserves at its top.
    @State private var bandHeight: CGFloat = 0
    /// Cached result of a cheap fetchCount — avoids faulting catalogue.items on every render.
    @State private var hasRecentlyDeletedItems = false
#if os(iOS)
    /// An export chosen from the toolbar, waiting for `ShareSheetAnchor` to present it.
    @State private var pendingExport: NSItemProvider?
#endif

    /// Updates `hasRecentlyDeletedItems` via a single fetchLimit-1 count — no object
    /// materialisation, O(1) via the deletedDate index.
    private func refreshHasRecentlyDeleted() {
        let id = catalogue.persistentModelID
        var descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == id && $0.deletedDate != nil }
        )
        descriptor.fetchLimit = 1
        hasRecentlyDeletedItems = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private var itemCountLabel: String {
        displayedCount == 1 ? "1 item" : "\(displayedCount) items"
    }

    private var statusTabs: [StatusTabDescriptor] {
        catalogue.statusTabDescriptors
    }

    private var flagFields: [FieldDefinition] {
        catalogue.flagFields
    }

    /// Drops selections that no longer exist — the status field can be reconfigured here
    /// or, via iCloud, on another device while this view is open. Without this the list
    /// would filter on a tab the picker no longer shows, appearing permanently empty.
    private func reconcileFilterSelections() {
        let resolved = catalogue.resolvedStatusTab(selectedTab)
        if resolved != selectedTab { selectedTab = resolved }

        let liveFlagIDs = Set(flagFields.map(\.fieldID))
        if !activeFlagIDs.isSubset(of: liveFlagIDs) {
            activeFlagIDs.formIntersection(liveFlagIDs)
        }
    }
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    /// Whether the catalogue's colour arrives as the band — only where the list is pushed on
    /// its own. Beside a detail column the colour is the wash's glow instead, drawn the same in
    /// both columns and fixed to the screen: a band scrolling away in one column while the
    /// other stayed still left their top edges disagreeing at almost every scroll position.
    private var usesBand: Bool {
#if os(macOS)
        false
#else
        !hasDetailColumn
#endif
    }

    // MARK: - Body

    var body: some View {
        CatalogueItemsView(
            catalogue: catalogue,
            statusTab: selectedTab,
            activeFlagIDs: Array(activeFlagIDs),
            searchText: appliedSearchText,
            sortFieldKey: $catalogue.sortFieldKey,
            sortDirection: $catalogue.sortDirection,
            selectedItem: $selectedItem,
            displayedCount: $displayedCount,
            scrollState: bandScroll,
            trackedScrollRange: usesBand ? bandHeight : 0,
            header: {
                // Room for the band floating over the list, plus the gap above the first
                // card; beside a detail column, just the gap below the bar or the tabs.
                Color.clear
                    .frame(height: usesBand ? bandHeight + 12 : 8)
                    .accessibilityHidden(true)
            }
        )
#if os(iOS)
        // Under the trailing end of the bar, where the Export menu (or the overflow holding
        // it) sits, so the share popover points back at what the user tapped.
        .overlay(alignment: .topTrailing) {
            ShareSheetAnchor(itemProvider: $pendingExport)
                .frame(width: 1, height: 1)
                .padding(.trailing, 28)
                .accessibilityHidden(true)
        }
#endif
        .overlay(alignment: .top) {
            if usesBand {
                CatalogueBand(
                    catalogue: catalogue,
                    itemCount: displayedCount,
                    scrollState: bandScroll,
                    height: $bandHeight,
                    isTitleCollapsed: $isBandScrolledAway
                ) {
                    // The tabs ride up with the band and then stay on its strip: the filter is
                    // wanted while scrolling, and it is short. They exist only when the
                    // catalogue defines a status field; without them the strip is just the
                    // colour under the bar.
                    if !statusTabs.isEmpty {
                        StatusTabBar(tabs: statusTabs, catalogue: catalogue, selection: $selectedTab, onFill: true)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .safeAreaBar(edge: .top) {
            // Beside a detail column there is no band to carry the tabs. As a bar they sit on
            // the glow and inside the soft scroll edge, so the cards blur out before they
            // reach them rather than passing sharply beneath.
            if !usesBand && !statusTabs.isEmpty {
                StatusTabBar(tabs: statusTabs, catalogue: catalogue, selection: $selectedTab)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
        // A soft edge fades and blurs the cards progressively as they pass under the bar,
        // rather than a hard line.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(CatalogueWash(catalogue: catalogue, glow: !usesBand))
        .tint(catalogue.palette(for: colorScheme).tint)
#if os(macOS)
        // The window title has nowhere else to come from.
        .navigationTitle(catalogue.name)
        .navigationSubtitle(itemCountLabel)
        .navigationSplitViewColumnWidth(min: 280, ideal: 360)
#else
        .navigationTitle(catalogue.name)
        .navigationSubtitle(usesBand ? "" : itemCountLabel)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            // Over the band the bar sits on the catalogue's fill, which may have gone either
            // way, so the title is drawn here in the band's own label colours. Not
            // `toolbarColorScheme`: that flips the whole bar's scheme, and the glass buttons
            // came out looking foreign on the fill. The band stands in for the title on
            // arrival, so this only fades in once the band's title row has collapsed.
            if usesBand {
                ToolbarItem(placement: .principal) {
                    BandBarTitle(catalogue: catalogue, countLabel: itemCountLabel)
                        .opacity(isBandScrolledAway ? 1 : 0)
                        .accessibilityHidden(!isBandScrolledAway)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
#endif
        .searchable(text: $searchText)
        .onChange(of: searchText) { _, newValue in
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                if newValue == searchText {
                    appliedSearchText = newValue
                }
            }
        }
        .sheet(isPresented: $showingEditCatalogue) {
            AddEditCatalogueView(catalogue: catalogue)
        }
        .onChange(of: statusTabs) { reconcileFilterSelections() }
        .onChange(of: flagFields.map(\.fieldID)) { reconcileFilterSelections() }
        .sheet(isPresented: $showingAddItem) {
            AddEditItemView(catalogue: catalogue, defaultStatusTab: selectedTab)
        }
        .sheet(isPresented: $showingStats) {
            CatalogueStatsView(catalogue: catalogue)
        }
        .sheet(isPresented: $showingRecentlyDeleted) {
            RecentlyDeletedView(catalogue: catalogue)
        }
        .task(id: catalogue.persistentModelID) {
            if seededCatalogueID != catalogue.persistentModelID {
                seededCatalogueID = catalogue.persistentModelID
                selectedTab = catalogue.defaultStatusTab
            }
            reconcileFilterSelections()
            PurgeService.purgeExpiredItems(for: catalogue, in: modelContext)
            // Refresh after purge — purging expired items may clear the deleted set.
            refreshHasRecentlyDeleted()
        }
        .onChange(of: displayedCount) {
            // A soft-delete or restore changes displayedCount; refresh so the toolbar
            // entry appears/disappears without faulting the full items relationship.
            refreshHasRecentlyDeleted()
        }
#if !os(macOS)
        .navigationDestination(
            item: Binding(
                get: { hasDetailColumn ? nil : selectedItem },
                set: { selectedItem = $0 }
            )
        ) { item in
            ItemDetailView(catalogue: catalogue, item: item, selectedItem: $selectedItem)
        }
#endif
        .toolbar {
#if os(iOS)
            // Add is the one primary action. Everything else is `.secondaryAction`, which the
            // system keeps in the bar while there is room and folds into its own overflow
            // menu when there isn't — so the flag filter collapses into the same "…" as the
            // rest, rather than a hand-rolled menu sitting beside it and crowding the bar.
            ToolbarItem(placement: .primaryAction) {
                AddItemButton(showingAddItem: $showingAddItem)
            }
            if !flagFields.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    FlagFilterButton(flagFields: flagFields, activeFlagIDs: $activeFlagIDs)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                LayoutToggleButton(layout: $catalogue.itemLayout)
            }
            ToolbarItem(placement: .secondaryAction) {
                SortMenuButton(catalogue: catalogue, sortFieldKey: $catalogue.sortFieldKey, sortDirection: $catalogue.sortDirection)
            }
            ToolbarItem(placement: .secondaryAction) {
                ExportMenuItems(catalogue: catalogue) { format in
                    pendingExport = format.itemProvider(for: catalogue)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                CatalogueEditButton(showingEditCatalogue: $showingEditCatalogue)
            }
            if hasRecentlyDeletedItems {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingRecentlyDeleted = true
                    } label: {
                        Label("Recently Deleted", systemImage: "trash.circle")
                    }
                }
            }
#else
            ToolbarItem(placement: .primaryAction) {
                AddItemButton(showingAddItem: $showingAddItem)
            }
            if !flagFields.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    FlagFilterButton(flagFields: flagFields, activeFlagIDs: $activeFlagIDs)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                LayoutToggleButton(layout: $catalogue.itemLayout)
            }
            ToolbarItem(placement: .primaryAction) {
                SortMenuButton(catalogue: catalogue, sortFieldKey: $catalogue.sortFieldKey, sortDirection: $catalogue.sortDirection)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    ExportMenuItems(catalogue: catalogue)
                    Button {
                        showingStats = true
                    } label: {
                        Label("Statistics", systemImage: "chart.bar")
                    }
                    CatalogueEditButton(showingEditCatalogue: $showingEditCatalogue)
                    if hasRecentlyDeletedItems {
                        Divider()
                        Button {
                            showingRecentlyDeleted = true
                        } label: {
                            Label("Recently Deleted", systemImage: "trash.circle")
                        }
                    }
                }
            }
#endif
        }
    }
}

// MARK: - Export Menu Items

/// Isolated subview so that export data is never computed during search keystrokes.
/// CatalogueDetailView re-renders on every keystroke (@State searchText changes), but
/// SwiftUI only re-renders this view when `catalogue` properties it accessed actually change.
private struct ExportMenuItems: View {
    let catalogue: Catalogue
#if os(iOS)
    /// Not `ShareLink`: this menu can end up in the bar's overflow, which leaves the share
    /// sheet nothing to anchor on and crashes. See `ShareSheetAnchor`.
    let onExport: (CatalogueExportFormat) -> Void
#endif

    var body: some View {
        Menu("Export", systemImage: "square.and.arrow.up") {
            ForEach(CatalogueExportFormat.allCases) { format in
#if os(iOS)
                Button(format.title, systemImage: format.systemImage) {
                    onExport(format)
                }
#else
                exportLink(for: format)
#endif
            }
        }
    }

#if !os(iOS)
    @ViewBuilder
    private func exportLink(for format: CatalogueExportFormat) -> some View {
        let filename = format.filename(for: catalogue)
        let preview = SharePreview(filename, image: Image(systemName: format.systemImage))
        switch format {
        case .csv:
            ShareLink(format.title, item: CatalogueCSVFile(catalogue: catalogue, filename: filename), preview: preview)
        case .jsonWithPhotos:
            ShareLink(format.title, item: CatalogueJSONFile(catalogue: catalogue, includePhotos: true, filename: filename), preview: preview)
        case .jsonWithoutPhotos:
            ShareLink(format.title, item: CatalogueJSONFile(catalogue: catalogue, includePhotos: false, filename: filename), preview: preview)
        }
    }
#endif
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field1 = FieldDefinition(name: "Manufacturer", fieldType: .text, priority: 0)
    field1.catalogue = catalogue
    container.mainContext.insert(field1)

    let field2 = FieldDefinition(name: "Year", fieldType: .number, priority: 1)
    field2.catalogue = catalogue
    container.mainContext.insert(field2)

    let item1 = CatalogueItem()
    item1.catalogue = catalogue
    container.mainContext.insert(item1)

    let val1 = FieldValue(fieldDefinition: field1, fieldType: .text)
    val1.textValue = "Airfix"
    val1.item = item1
    container.mainContext.insert(val1)

    let item2 = CatalogueItem()
    item2.catalogue = catalogue
    container.mainContext.insert(item2)

    let val2 = FieldValue(fieldDefinition: field1, fieldType: .text)
    val2.textValue = "Tamiya"
    val2.item = item2
    container.mainContext.insert(val2)

    return NavigationStack {
        CatalogueDetailView(catalogue: catalogue, selectedItem: .constant(nil))
    }
    .modelContainer(container)
}
