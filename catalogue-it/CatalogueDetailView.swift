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

    @AppStorage("itemLayoutPreference") private var isGridLayout: Bool = true
    @State private var selectedTab: ItemTab = .owned
    @State private var showingEditCatalogue = false
    @State private var showingAddItem = false

    private var currentItems: [CatalogueItem] {
        let items = selectedTab == .owned ? catalogue.ownedItems : catalogue.wishlistItems
        return items.sorted { $0.createdDate < $1.createdDate }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
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
                CatalogueEmptyStateView(selectedTab: selectedTab)
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
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                layoutToggleButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                addItemButton
            }
            ToolbarItem(placement: .topBarLeading) {
                editCatalogueButton
            }
#else
            ToolbarItem(placement: .primaryAction) {
                addItemButton
            }
            ToolbarItem(placement: .primaryAction) {
                layoutToggleButton
            }
            ToolbarItem(placement: .primaryAction) {
                editCatalogueButton
            }
#endif
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
    }
}

// MARK: - Empty State View

private struct CatalogueEmptyStateView: View {
    let selectedTab: ItemTab

    var body: some View {
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
