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

    @AppStorage("itemLayoutPreference")  private var isGridLayout: Bool = true
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

    private var currentItems: [CatalogueItem] {
        let tabItems = selectedTab == .owned ? catalogue.ownedItems : catalogue.wishlistItems
        let searched = searchText.isEmpty ? tabItems : tabItems.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            item.fieldValues.contains { $0.displayValue.localizedCaseInsensitiveContains(searchText) }
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
        let tabItems = selectedTab == .owned ? catalogue.ownedItems : catalogue.wishlistItems

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
                    isFiltered: !searchText.isEmpty && !tabItems.isEmpty
                )
            } else if isGridLayout {
                CatalogueItemGridView(items: currentItems, gridColumns: gridColumns)
            } else {
                CatalogueItemListView(items: currentItems, catalogue: catalogue)
            }
        }
        .navigationTitle(catalogue.name)
        .navigationDestination(for: CatalogueItem.self) { item in
            ItemDetailView(catalogue: catalogue, item: item)
        }
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
                Menu {
                    editCatalogueButton
                    Button {
                        showingStats = true
                    } label: {
                        Label("Statistics", systemImage: "chart.bar")
                    }
                    ShareLink(item: csvFile, preview: SharePreview("\(catalogue.name).csv", image: Image(systemName: "tablecells")))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                sortMenuButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                layoutToggleButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                addItemButton
            }
#else
            ToolbarItem(placement: .primaryAction) {
                addItemButton
            }
            ToolbarItem(placement: .primaryAction) {
                layoutToggleButton
            }
            ToolbarItem(placement: .primaryAction) {
                sortMenuButton
            }
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: csvFile, preview: SharePreview("\(catalogue.name).csv", image: Image(systemName: "tablecells")))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingStats = true
                } label: {
                    Label("Statistics", systemImage: "chart.bar")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                editCatalogueButton
            }
#endif
        }
    }

    // MARK: - Toolbar Buttons

    private var editCatalogueButton: some View {
        Button {
            showingEditCatalogue = true
        } label: {
            Label("Edit Catalogue", systemImage: "pencil")
        }
    }

    private var layoutToggleButton: some View {
        Button {
            isGridLayout.toggle()
        } label: {
            Label(
                isGridLayout ? "Switch to List" : "Switch to Grid",
                systemImage: isGridLayout ? "list.bullet" : "square.grid.2x2"
            )
        }
    }

    private var addItemButton: some View {
        Button {
            showingAddItem = true
        } label: {
            Label("Add Item", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
    }

    private var sortMenuButton: some View {
        // The built-in "Name" sort uses displayName, which is derived from the first text
        // field. Exclude that field from the custom list to avoid showing it twice.
        let firstTextField = catalogue.fieldDefinitions
            .filter { $0.fieldType == .text }
            .min(by: { $0.sortOrder < $1.sortOrder })
        let customFields = catalogue.fieldDefinitions
            .filter { $0.persistentModelID != firstTextField?.persistentModelID }
            .sorted { $0.sortOrder < $1.sortOrder }

        return Menu {
            Picker("Sort By", selection: $sortFieldKey) {
                Text("Date Added").tag(ItemSortField.dateAdded.rawValue)
                Text("Name").tag(ItemSortField.name.rawValue)
                ForEach(customFields) { field in
                    Text(field.name).tag(ItemSortField.field(field.name).rawValue)
                }
            }
            Picker("Direction", selection: $sortDirection) {
                Text("Ascending").tag(ItemSortDirection.ascending.rawValue)
                Text("Descending").tag(ItemSortDirection.descending.rawValue)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}

// MARK: - Empty State View

private struct CatalogueEmptyStateView: View {
    let selectedTab: ItemTab
    let isFiltered: Bool

    var body: some View {
        if isFiltered {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView(
                "No Items Yet",
                systemImage: selectedTab == .owned ? "checkmark.circle" : "heart",
                description: Text(
                    selectedTab == .owned
                        ? "Tap + to add your first owned item"
                        : "Tap + to add your first wishlist item"
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Item Grid View

private struct CatalogueItemGridView: View {
    let items: [CatalogueItem]
    let gridColumns: [GridItem]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        ItemCardView(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

// MARK: - Item List View

private struct CatalogueItemListView: View {
    let items: [CatalogueItem]
    let catalogue: Catalogue

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    ItemRowView(item: item, catalogue: catalogue)
                }
            }
        }
        .listStyle(.plain)
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
        CatalogueDetailView(catalogue: catalogue)
    }
    .modelContainer(container)
}
