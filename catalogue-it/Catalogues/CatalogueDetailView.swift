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
#if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// Drives the field when `drawsOwnSearchButton` stands in for the system's.
    @State private var isSearchPresented = false
#endif

    @State private var selectedTab: StatusTab = .all
    /// Seeding is keyed on the catalogue: `.task` re-runs whenever the view comes back, including
    /// returning from an item in compact width, and would otherwise throw the user's tab away.
    @State private var seededCatalogueID: PersistentIdentifier?
    /// ANDed with each other and with the status tab.
    @State private var activeFlagIDs: Set<UUID> = []
    @State private var showingEditCatalogue = false
    @State private var showingAddItem = false
    @State private var showingStats = false
    @State private var showingRecentlyDeleted = false
    @State private var searchText: String = ""
    @State private var appliedSearchText: String = ""
    @State private var displayedCount: Int = 0
    @State private var isBandScrolledAway = false
    @State private var bandScroll = BandScrollState()
    @State private var bandHeight: CGFloat = 0
    /// A cached fetchCount, so rendering never faults `catalogue.items`.
    @State private var hasRecentlyDeletedItems = false
    @State private var selection = ItemSelectionState()
    @State private var exportRequest: ExportRequest?
#if os(iOS)
    @State private var pendingBackup: [NSItemProvider]?
#endif

    private func refreshHasRecentlyDeleted() {
        let id = catalogue.persistentModelID
        var descriptor = FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == id && $0.deletedDate != nil }
        )
        descriptor.fetchLimit = 1
        hasRecentlyDeletedItems = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private var filterFingerprint: FilterFingerprint {
        FilterFingerprint(
            catalogue: catalogue,
            statusTab: selectedTab,
            activeFlagIDs: Array(activeFlagIDs),
            searchText: appliedSearchText
        )
    }

    private func exportCatalogue() {
        let fingerprint = filterFingerprint
        let filters = ExportFilters(
            fingerprint: fingerprint,
            allCount: CatalogueSummary.itemCount(for: catalogue, in: modelContext)
        )
        Task {
            exportRequest = await selection.prepareExport(
                .matching(fingerprint, excluding: []),
                format: .spreadsheet,
                filters: filters,
                container: modelContext.container,
                context: modelContext,
                current: fingerprint
            )
        }
    }

    private var selectedCount: Int {
        selection.count(totalMatching: displayedCount)
    }

    private var selectionTitle: String {
        String(localized: "\(selectedCount) Selected")
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

    /// The status field can be reconfigured, here or on another device, while this is open; a
    /// tab the picker no longer shows would leave the list permanently empty.
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

    /// Only where the list is pushed on its own; beside a detail column the colour is the glow,
    /// fixed to the screen (see `CatalogueWash.glow`).
    private var usesBand: Bool {
#if os(macOS)
        false
#else
        !hasDetailColumn
#endif
    }

    /// macOS keeps its own window chrome and the system edge effect.
    private var sharesGlowWithDetail: Bool {
#if os(iOS)
        hasDetailColumn
#else
        false
#endif
    }

#if os(iOS)
    /// In a compact-height window beside a detail column (a large iPhone in landscape) the
    /// system's minimised search lands in a bottom bar floating over both columns, and top-bar
    /// placement can't be requested, so the column gets a search button of our own. iPad never
    /// has a compact-height window and keeps the system's.
    private var drawsOwnSearchButton: Bool {
        hasDetailColumn && verticalSizeClass == .compact
    }

    private var searchPlacement: SearchFieldPlacement {
        drawsOwnSearchButton ? .navigationBarDrawer(displayMode: .automatic) : .automatic
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        let allSelected = displayedCount > 0 && selectedCount >= displayedCount
        ToolbarItem(placement: .topBarLeading) {
            Button(allSelected ? "Deselect All" : "Select All") {
                if allSelected { selection.deselectAll() } else { selection.selectAll(filterFingerprint) }
            }
            .accessibilityIdentifier("selectAllButton")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { selection.end() }
                .accessibilityIdentifier("selectDoneButton")
        }
    }
#endif

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
            selection: selection,
            header: {
                if sharesGlowWithDetail {
                    ListHeader(
                        catalogue: catalogue,
                        countLabel: selection.isSelecting ? selectionTitle : itemCountLabel,
                        statusTabs: statusTabs,
                        selectedTab: $selectedTab
                    )
                } else {
                    // Room for the floating band plus the gap above the first card.
                    Color.clear
                        .frame(height: usesBand ? bandHeight + 12 : 8)
                        .accessibilityHidden(true)
                }
            }
        )
        // Inside the tabs' `safeAreaBar`, so the fade runs under them too.
        .washFadeEdge(sharesGlowWithDetail)
#if os(iOS)
        // Under the Back Up menu (or the overflow holding it), so the popover points at it.
        .overlay(alignment: .topTrailing) {
            ShareSheetAnchor(itemProviders: $pendingBackup)
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
                    // The tabs ride up with the band, then stay on its strip.
                    if !statusTabs.isEmpty {
                        StatusTabBar(tabs: statusTabs, colorHex: catalogue.colorHex, selection: $selectedTab, onFill: true)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .safeAreaBar(edge: .top) {
            // macOS has no band to carry the tabs.
            if !usesBand && !sharesGlowWithDetail && !statusTabs.isEmpty {
                StatusTabBar(tabs: statusTabs, colorHex: catalogue.colorHex, selection: $selectedTab)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .catalogueGround(catalogue, glow: !usesBand, inSplitView: sharesGlowWithDetail)
        .tint(catalogue.palette(for: colorScheme).tint)
#if os(macOS)
        .navigationTitle(catalogue.name)
        .navigationSubtitle(itemCountLabel)
        .navigationSplitViewColumnWidth(min: 280, ideal: 360)
#else
        .navigationTitle(catalogue.name)
        // The band or list header carries the name and count. Beside a detail column the narrow bar
        // is full of buttons, so the title is removed rather than truncated; it stays set for
        // accessibility and the window title.
        .navigationSubtitle(usesBand || hasDetailColumn ? "" : itemCountLabel)
        .toolbarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(selection.isSelecting)
        .toolbar(removing: hasDetailColumn ? .title : nil)
        .toolbar {
            // Drawn in the band's label colours, since the fill may be light or dark. Not
            // `toolbarColorScheme`, which made the glass buttons look foreign on the fill.
            // Beside a detail column the title is removed, and `ListHeader` carries the count.
            if usesBand {
                ToolbarItem(placement: .principal) {
                    if selection.isSelecting {
                        Text(selectionTitle)
                            .font(.headline)
                            .contentTransition(.numericText())
                    } else {
                        BandBarTitle(catalogue: catalogue, countLabel: itemCountLabel)
                            .opacity(isBandScrolledAway ? 1 : 0)
                            .accessibilityHidden(!isBandScrolledAway)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
#endif
#if os(iOS)
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: searchPlacement)
#else
        .searchable(text: $searchText)
#endif
#if os(iOS)
        // Beside a detail column iOS would draw the field as a full-width row above the tabs.
        .searchToolbarBehavior(hasDetailColumn ? .minimize : .automatic)
#endif
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
        .sheet(item: $exportRequest) { request in
            ExportComposerView(catalogue: catalogue, request: request)
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
            selection.end()
            reconcileFilterSelections()
            PurgeService.purgeExpiredItems(for: catalogue, in: modelContext)
            // Purging can empty the deleted set.
            refreshHasRecentlyDeleted()
        }
        .onChange(of: displayedCount) {
            // A soft-delete or restore changes displayedCount.
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
            if selection.isSelecting {
                selectionToolbar
            } else {
                // The rest are `.secondaryAction`, kept in the bar while there's room and folded into the
                // system's overflow when not.
                ToolbarItem(placement: .primaryAction) {
                    AddItemButton(showingAddItem: $showingAddItem)
                }
                // See `drawsOwnSearchButton`.
                if drawsOwnSearchButton {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Search", systemImage: "magnifyingglass") {
                            isSearchPresented = true
                        }
                    }
                }
                if !flagFields.isEmpty {
                    ToolbarItem(placement: .secondaryAction) {
                        FlagFilterButton(flagFields: flagFields, activeFlagIDs: $activeFlagIDs)
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Select", systemImage: "checkmark.circle") { selection.begin() }
                        .accessibilityIdentifier("selectButton")
                        .disabled(displayedCount == 0)
                }
                ToolbarItem(placement: .secondaryAction) {
                    LayoutToggleButton(layout: $catalogue.itemLayout)
                }
                ToolbarItem(placement: .secondaryAction) {
                    SortMenuButton(catalogue: catalogue, sortFieldKey: $catalogue.sortFieldKey, sortDirection: $catalogue.sortDirection)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Export…", systemImage: "square.and.arrow.up") { exportCatalogue() }
                        .keyboardShortcut("e")
                        .accessibilityIdentifier("exportButton")
                        .disabled(displayedCount == 0)
                }
                ToolbarItem(placement: .secondaryAction) {
                    BackUpMenuItems(catalogue: catalogue) { format in
                        pendingBackup = [format.itemProvider(for: catalogue)]
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
                    BackUpMenuItems(catalogue: catalogue)
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

// MARK: - List Header

/// Name, count and tabs scroll away with the items beside a detail column: the narrow bar has
/// no room for a readable title, and the list wants the height more than pinned tabs.
private struct ListHeader: View {
    let catalogue: Catalogue
    let countLabel: String
    let statusTabs: [StatusTabDescriptor]
    @Binding var selectedTab: StatusTab

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(catalogue.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text(countLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if !statusTabs.isEmpty {
                StatusTabBar(tabs: statusTabs, colorHex: catalogue.colorHex, selection: $selectedTab)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Back Up Menu Items

/// Its own view so backup data isn't computed on every search keystroke.
private struct BackUpMenuItems: View {
    let catalogue: Catalogue
#if os(iOS)
    /// Not `ShareLink`: in the bar's overflow the share sheet has nothing to anchor on and
    /// crashes. See `ShareSheetAnchor`.
    let onBackUp: (CatalogueExportFormat) -> Void
#endif

    var body: some View {
        Menu("Back Up Catalogue", systemImage: "externaldrive") {
            ForEach(CatalogueExportFormat.allCases) { format in
#if os(iOS)
                Button(format.title, systemImage: format.systemImage) {
                    onBackUp(format)
                }
#else
                backUpLink(for: format)
#endif
            }
        }
    }

#if !os(iOS)
    private func backUpLink(for format: CatalogueExportFormat) -> some View {
        let filename = format.filename(for: catalogue)
        return ShareLink(
            format.title,
            item: CatalogueJSONFile(catalogue: catalogue, includePhotos: format == .jsonWithPhotos, filename: filename),
            preview: SharePreview(filename, image: Image(systemName: format.systemImage))
        )
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
