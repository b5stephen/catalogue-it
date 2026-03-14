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

    var body: some View {
        NavigationSplitView {
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
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
        } detail: {
            if let catalogue = selectedCatalogue {
                NavigationStack {
                    CatalogueDetailView(catalogue: catalogue)
                }
            } else {
                Text("Select a catalogue")
                    .foregroundStyle(.secondary)
            }
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
