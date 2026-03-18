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
    let catalogue: Catalogue
    @Binding var selectedItem: CatalogueItem?

#if os(macOS)
    @AppStorage("itemLayoutStyle_mac")   private var layout: ItemLayout = .table
#else
    @AppStorage("itemLayoutStyle_ios")   private var layout: ItemLayout = .grid
#endif
    @AppStorage("itemSortField")         private var sortFieldKey: String = ItemSortField.dateAdded.rawValue
    @AppStorage("itemSortDirection")     private var sortDirection: String = ItemSortDirection.ascending.rawValue

    @State private var selectedTab: ItemTab = .owned
    @State private var showingEditCatalogue = false
    @State private var showingAddItem = false
    @State private var showingStats = false
    @State private var searchText: String = ""

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    // MARK: - Computed Items

    private var baseItems: [CatalogueItem] {
        switch selectedTab {
        case .all:      catalogue.items
        case .owned:    catalogue.ownedItems
        case .wishlist: catalogue.wishlistItems
        }
    }

    private var currentItems: [CatalogueItem] {
        let searched = searchText.isEmpty ? baseItems : baseItems.filter { item in
            item.displayName.localizedStandardContains(searchText) ||
            item.fieldValues.contains { $0.displayValue.localizedStandardContains(searchText) }
        }
        return sortedItems(searched)
    }

    // MARK: - Sort Logic

    private func sortedItems(_ items: [CatalogueItem]) -> [CatalogueItem] {
        let field = ItemSortField(rawValue: sortFieldKey)
        let asc = (ItemSortDirection(rawValue: sortDirection) ?? .ascending) == .ascending

        return items.sorted { a, b in
            let result: Bool
            switch field {
            case .dateAdded:
                result = a.createdDate < b.createdDate
            case .name:
                result = a.displayName.localizedCompare(b.displayName) == .orderedAscending
            case .field(let name):
                let va = a.value(for: name)
                let vb = b.value(for: name)
                // nil sorts last regardless of direction
                guard let va else { return false }
                guard let vb else { return true }
                switch va.fieldType {
                case .text:
                    let ta = va.textValue ?? "", tb = vb.textValue ?? ""
                    result = ta.localizedCompare(tb) == .orderedAscending
                case .number:
                    result = (va.numberValue ?? 0) < (vb.numberValue ?? 0)
                case .date:
                    guard let da = va.dateValue, let db = vb.dateValue else {
                        return va.dateValue != nil
                    }
                    result = da < db
                case .boolean:
                    // false < true (unchecked first when ascending)
                    result = (va.boolValue == false) && (vb.boolValue == true)
                }
            }
            return asc ? result : !result
        }
    }

    // MARK: - CSV Export

    private var csvFile: CatalogueCSVFile {
        CatalogueCSVFile(
            content: CatalogueExporter.csvString(for: catalogue),
            filename: "\(catalogue.name).csv"
        )
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

            if currentItems.isEmpty {
                CatalogueEmptyStateView(
                    selectedTab: selectedTab,
                    isFiltered: !searchText.isEmpty && !baseItems.isEmpty
                )
            } else {
                switch layout {
                case .grid:
                    ItemGridView(items: currentItems, gridColumns: gridColumns, showWishlistBadge: selectedTab == .all, selectedItem: $selectedItem)
                case .list:
                    ItemListView(items: currentItems, catalogue: catalogue, showWishlistBadge: selectedTab == .all, selectedItem: $selectedItem)
                case .table:
                    ItemTableView(items: currentItems, catalogue: catalogue, showWishlistBadge: selectedTab == .all, selectedItem: $selectedItem)
                }
            }
        }
        .navigationTitle(catalogue.name)
#if os(macOS)
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
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Menu("More Options", systemImage: "ellipsis.circle") {
                    CatalogueEditButton(showingEditCatalogue: $showingEditCatalogue)
                    Button {
                        showingStats = true
                    } label: {
                        Label("Statistics", systemImage: "chart.bar")
                    }
                    ShareLink(item: csvFile, preview: SharePreview("\(catalogue.name).csv", image: Image(systemName: "tablecells")))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                SortMenuButton(catalogue: catalogue, sortFieldKey: $sortFieldKey, sortDirection: $sortDirection)
            }
            ToolbarItem(placement: .topBarTrailing) {
                LayoutToggleButton(layout: $layout)
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
                SortMenuButton(catalogue: catalogue, sortFieldKey: $sortFieldKey, sortDirection: $sortDirection)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    ShareLink(item: csvFile, preview: SharePreview("\(catalogue.name).csv", image: Image(systemName: "tablecells")))
                    Button {
                        showingStats = true
                    } label: {
                        Label("Statistics", systemImage: "chart.bar")
                    }
                    CatalogueEditButton(showingEditCatalogue: $showingEditCatalogue)
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

    let field1 = FieldDefinition(name: "Manufacturer", fieldType: .text, sortOrder: 0)
    field1.catalogue = catalogue
    container.mainContext.insert(field1)

    let field2 = FieldDefinition(name: "Year", fieldType: .number, sortOrder: 1)
    field2.catalogue = catalogue
    container.mainContext.insert(field2)

    let item1 = CatalogueItem(isWishlist: false)
    item1.catalogue = catalogue
    container.mainContext.insert(item1)

    let val1 = FieldValue(fieldName: "Manufacturer", fieldType: .text, sortOrder: 0)
    val1.textValue = "Airfix"
    val1.item = item1
    container.mainContext.insert(val1)

    let item2 = CatalogueItem(isWishlist: true)
    item2.catalogue = catalogue
    container.mainContext.insert(item2)

    let val2 = FieldValue(fieldName: "Manufacturer", fieldType: .text, sortOrder: 0)
    val2.textValue = "Tamiya"
    val2.item = item2
    container.mainContext.insert(val2)

    return NavigationStack {
        CatalogueDetailView(catalogue: catalogue, selectedItem: .constant(nil))
    }
    .modelContainer(container)
}
