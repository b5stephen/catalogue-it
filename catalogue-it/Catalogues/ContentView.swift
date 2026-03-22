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
    @Query(sort: \Catalogue.priority) private var catalogues: [Catalogue]
    @State private var showingAddCatalogue = false
    @State private var selectedCatalogue: Catalogue?
    @State private var selectedItem: CatalogueItem?
    @State private var catalogueToEdit: Catalogue?

#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } content: {
            if let catalogue = selectedCatalogue {
                CatalogueDetailView(catalogue: catalogue, selectedItem: $selectedItem)
            } else {
                ContentUnavailableView("Select a catalogue", systemImage: "square.grid.2x2")
            }
        } detail: {
#if os(macOS)
            if let catalogue = selectedCatalogue, let item = selectedItem {
                ItemDetailView(catalogue: catalogue, item: item, selectedItem: $selectedItem)
            } else {
                ContentUnavailableView("Select an item", systemImage: "cube")
            }
#else
            if horizontalSizeClass != .compact, let catalogue = selectedCatalogue, let item = selectedItem {
                ItemDetailView(catalogue: catalogue, item: item, selectedItem: $selectedItem)
            } else {
                ContentUnavailableView("Select an item", systemImage: "cube")
            }
#endif
        }
        .onChange(of: selectedCatalogue) {
            selectedItem = nil
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selectedCatalogue) {
            ForEach(catalogues) { catalogue in
                NavigationLink(value: catalogue) {
                    CatalogueRow(catalogue: catalogue)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        catalogueToEdit = catalogue
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)

                    Button(role: .destructive) {
                        withAnimation {
                            if selectedCatalogue == catalogue {
                                selectedCatalogue = nil
                            }
                            modelContext.delete(catalogue)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        catalogueToEdit = catalogue
                    } label: {
                        Label("Edit Catalogue", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        withAnimation {
                            if selectedCatalogue == catalogue {
                                selectedCatalogue = nil
                            }
                            modelContext.delete(catalogue)
                        }
                    } label: {
                        Label("Delete Catalogue", systemImage: "trash")
                    }
                }
            }
            .onMove(perform: moveCatalogues)
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
            AddEditCatalogueView(nextPriority: catalogues.count)
        }
        .sheet(item: $catalogueToEdit) { catalogue in
            AddEditCatalogueView(catalogue: catalogue, nextPriority: catalogues.count)
        }
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
