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
    @State private var displayedCount: Int = 0

    private var hasRecentlyDeletedItems: Bool {
        catalogue.items.contains { $0.deletedDate != nil }
    }

    private var countLabel: String {
        displayedCount == 1 ? "1 item" : "\(displayedCount) items"
    }
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    // MARK: - Export Files

    private var csvFile: CatalogueCSVFile {
        CatalogueCSVFile(
            content: CatalogueExporter.csvString(for: catalogue),
            filename: "\(catalogue.name).csv"
        )
    }

    private var jsonFile: CatalogueJSONFile? {
        guard let data = try? CatalogueExporter.jsonData(for: catalogue) else { return nil }
        return CatalogueJSONFile(data: data, filename: "\(catalogue.name).json")
    }

    private var jsonFileNoPhotos: CatalogueJSONFile? {
        guard let data = try? CatalogueExporter.jsonData(for: catalogue, includePhotos: false) else { return nil }
        return CatalogueJSONFile(data: data, filename: "\(catalogue.name).json")
    }

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
                searchText: searchText,
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
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        ShareLink(item: csvFile, preview: SharePreview("\(catalogue.name).csv", image: Image(systemName: "tablecells")))
                        if let jsonFile {
                            ShareLink("Export as JSON (with Photos)", item: jsonFile, preview: SharePreview("\(catalogue.name).json", image: Image(systemName: "doc.text")))
                        }
                        if let jsonFileNoPhotos {
                            ShareLink("Export as JSON (no Photos)", item: jsonFileNoPhotos, preview: SharePreview("\(catalogue.name).json", image: Image(systemName: "doc.text")))
                        }
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
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        ShareLink(item: csvFile, preview: SharePreview("\(catalogue.name).csv", image: Image(systemName: "tablecells")))
                        if let jsonFile {
                            ShareLink("Export as JSON (with Photos)", item: jsonFile, preview: SharePreview("\(catalogue.name).json", image: Image(systemName: "doc.text")))
                        }
                        if let jsonFileNoPhotos {
                            ShareLink("Export as JSON (no Photos)", item: jsonFileNoPhotos, preview: SharePreview("\(catalogue.name).json", image: Image(systemName: "doc.text")))
                        }
                    }
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
