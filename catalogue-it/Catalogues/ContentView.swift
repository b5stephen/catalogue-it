//
//  ContentView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Catalogue.createdDate) private var catalogues: [Catalogue]
    @State private var showingAddCatalogue = false
    @State private var selectedCatalogue: Catalogue?
    @State private var selectedItem: CatalogueItem?

#if os(macOS)
    @AppStorage("itemLayoutStyle_mac") private var layout: ItemLayout = .table
#else
    @AppStorage("itemLayoutStyle_ios") private var layout: ItemLayout = .grid
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var isTableMode: Bool {
#if os(macOS)
        layout == .table
#else
        layout == .table && horizontalSizeClass == .regular
#endif
    }

    var body: some View {
        if isTableMode {
            NavigationSplitView {
                sidebarContent
            } detail: {
                if let catalogue = selectedCatalogue {
                    CatalogueDetailView(catalogue: catalogue, selectedItem: $selectedItem)
                } else {
                    ContentUnavailableView("Select a catalogue", systemImage: "square.grid.2x2")
                }
            }
            .onChange(of: selectedCatalogue) {
                selectedItem = nil
            }
        } else {
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
                    ContentUnavailableView("Select an item", systemImage: "cube")
                }
            }
            .onChange(of: selectedCatalogue) {
                selectedItem = nil
            }
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selectedCatalogue) {
            ForEach(catalogues) { catalogue in
                NavigationLink(value: catalogue) {
                    CatalogueRow(catalogue: catalogue)
                }
            }
            .onDelete(perform: deleteCatalogues)
        }
        .navigationTitle("My Catalogues")
        .overlay {
            if catalogues.isEmpty {
                ContentUnavailableView(
                    "No Catalogues",
                    systemImage: "square.grid.2x2",
                    description: Text("Create your first catalogue to start organizing your collections")
                )
            }
        }
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
#endif
            ToolbarItem {
                Button("Add Catalogue", systemImage: "plus") {
                    showingAddCatalogue = true
                }
            }
        }
        .sheet(isPresented: $showingAddCatalogue) {
            AddEditCatalogueView()
        }
    }

    private func deleteCatalogues(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(catalogues[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Catalogue.self, inMemory: true)
}
