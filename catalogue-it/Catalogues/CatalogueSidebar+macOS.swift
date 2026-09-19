//
//  CatalogueSidebar+macOS.swift
//  catalogue-it
//

#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Catalogue Sidebar (macOS)

/// The catalogue list in the sidebar column on macOS: compact `CatalogueRow`s in a standard
/// sidebar, where selection drives the content column of a three-column split view. The Mac
/// keeps all three panes — there is room for them, and a Mac user expects the sidebar to stay
/// put — so this is a `List(selection:)`, never a stack of links.
struct MacCatalogueSidebar: View {
    let catalogues: [Catalogue]
    @Binding var selectedCatalogue: Catalogue?
    let onEdit: (Catalogue) -> Void
    let onDelete: (Catalogue) -> Void
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        List(selection: $selectedCatalogue) {
            ForEach(catalogues) { catalogue in
                CatalogueRow(catalogue: catalogue)
                    .tag(catalogue)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            onEdit(catalogue)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)

                        Button(role: .destructive) {
                            onDelete(catalogue)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            onEdit(catalogue)
                        } label: {
                            Label("Edit Catalogue", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            onDelete(catalogue)
                        } label: {
                            Label("Delete Catalogue", systemImage: "trash")
                        }
                    }
            }
            .onMove(perform: onMove)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}
#endif
