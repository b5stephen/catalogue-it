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

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(catalogues) { catalogue in
                    NavigationLink {
                        CatalogueDetailPlaceholder(catalogue: catalogue)
                    } label: {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: { showingAddCatalogue = true }) {
                        Label("Add Catalogue", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCatalogue) {
                AddEditCatalogueView()
            }
        } detail: {
            Text("Select a catalogue")
                .foregroundStyle(.secondary)
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

// MARK: - Catalogue Row

struct CatalogueRow: View {
    let catalogue: Catalogue
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon with color
            Image(systemName: catalogue.iconName)
                .font(.title2)
                .foregroundStyle(Color(hex: catalogue.colorHex))
                .frame(width: 40, height: 40)
                .background(Color(hex: catalogue.colorHex).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(catalogue.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label("\(catalogue.ownedItems.count)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label("\(catalogue.wishlistItems.count)", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Placeholder Detail View

struct CatalogueDetailPlaceholder: View {
    let catalogue: Catalogue
    @State private var showingEditCatalogue = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: catalogue.iconName)
                .font(.system(size: 60))
                .foregroundStyle(Color(hex: catalogue.colorHex))
            
            Text(catalogue.name)
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Field Definitions:")
                    .font(.headline)
                
                ForEach(catalogue.fieldDefinitions.sorted(by: { $0.sortOrder < $1.sortOrder })) { field in
                    HStack {
                        Image(systemName: field.fieldType.icon)
                            .foregroundStyle(.secondary)
                        Text(field.name)
                        Spacer()
                        Text(field.fieldType.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text("Detail view coming in Phase 3! 🚀")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle(catalogue.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditCatalogue = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditCatalogue) {
            AddEditCatalogueView(catalogue: catalogue)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Catalogue.self, inMemory: true)
}
