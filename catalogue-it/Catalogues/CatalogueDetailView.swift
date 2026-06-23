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

#if os(macOS)
    @AppStorage("itemLayoutStyle_mac")   private var layout: ItemLayout = .list
#else
    @AppStorage("itemLayoutStyle_ios")   private var layout: ItemLayout = .list
#endif

#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var selectedTab: ItemTab = .owned
    @State private var showingEditCatalogue = false
    @State private var showingAddItem = false
    @State private var showingStats = false
    @State private var showingRecentlyDeleted = false
    @State private var searchText: String = ""
    @State private var appliedSearchText: String = ""
    @State private var displayedCount: Int = 0
    /// Cached result of a cheap fetchCount — avoids faulting catalogue.items on every render.
    @State private var hasRecentlyDeletedItems = false

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

    private var countLabel: String {
        displayedCount == 1 ? "1 item" : "\(displayedCount) items"
    }
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(ItemTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

#if !os(macOS)
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
#endif
            CatalogueItemsView(
                catalogue: catalogue,
                tab: selectedTab,
                searchText: appliedSearchText,
                sortFieldKey: $catalogue.sortFieldKey,
                sortDirection: $catalogue.sortDirection,
                layout: layout,
                selectedItem: $selectedItem,
                displayedCount: $displayedCount
            )
        }
        .navigationTitle(catalogue.name)
#if os(macOS)
        .navigationSubtitle(countLabel)
        .navigationSplitViewColumnWidth(min: 280, ideal: 360)
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
        .sheet(isPresented: $showingAddItem) {
            AddEditItemView(
                catalogue: catalogue,
                defaultIsWishlist: selectedTab == .wishlist
            )
        }
        .sheet(isPresented: $showingStats) {
            CatalogueStatsView(catalogue: catalogue)
        }
        .sheet(isPresented: $showingRecentlyDeleted) {
            RecentlyDeletedView(catalogue: catalogue)
        }
        .task(id: catalogue.persistentModelID) {
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
                get: { horizontalSizeClass == .compact ? selectedItem : nil },
                set: { selectedItem = $0 }
            )
        ) { item in
            ItemDetailView(catalogue: catalogue, item: item, selectedItem: $selectedItem)
        }
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    LayoutToggleButton(layout: $layout)
                    SortMenuButton(catalogue: catalogue, sortFieldKey: $catalogue.sortFieldKey, sortDirection: $catalogue.sortDirection)
                    Divider()
                    ExportMenuItems(catalogue: catalogue)
                    CatalogueEditButton(showingEditCatalogue: $showingEditCatalogue)
                    if hasRecentlyDeletedItems {
                        Divider()
                        Button {
                            showingRecentlyDeleted = true
                        } label: {
                            Label("Recently Deleted", systemImage: "trash.circle")
                        }
                    }
                } label: {
                    Label("More Options", systemImage: "ellipsis")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                AddItemButton(showingAddItem: $showingAddItem)
            }
#else
            ToolbarItem(placement: .primaryAction) {
                AddItemButton(showingAddItem: $showingAddItem)
            }
            ToolbarItem(placement: .primaryAction) {
                LayoutToggleButton(layout: $layout)
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

    var body: some View {
        Menu("Export", systemImage: "square.and.arrow.up") {
            ShareLink(
                item: CatalogueCSVFile(catalogue: catalogue, filename: "\(catalogue.name).csv"),
                preview: SharePreview("\(catalogue.name).csv", image: Image(systemName: "tablecells"))
            )
            ShareLink(
                "Export as JSON (with Photos)",
                item: CatalogueJSONFile(catalogue: catalogue, includePhotos: true, filename: "\(catalogue.name).json"),
                preview: SharePreview("\(catalogue.name).json", image: Image(systemName: "doc.text"))
            )
            ShareLink(
                "Export as JSON (no Photos)",
                item: CatalogueJSONFile(catalogue: catalogue, includePhotos: false, filename: "\(catalogue.name).json"),
                preview: SharePreview("\(catalogue.name).json", image: Image(systemName: "doc.text"))
            )
        }
    }
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

    let item1 = CatalogueItem(isWishlist: false)
    item1.catalogue = catalogue
    container.mainContext.insert(item1)

    let val1 = FieldValue(fieldDefinition: field1, fieldType: .text)
    val1.textValue = "Airfix"
    val1.item = item1
    container.mainContext.insert(val1)

    let item2 = CatalogueItem(isWishlist: true)
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
