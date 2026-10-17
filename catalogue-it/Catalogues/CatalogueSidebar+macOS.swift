//
//  CatalogueSidebar+macOS.swift
//  catalogue-it
//

#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Catalogue Sidebar (macOS)

/// Selection drives the content column of a three-column split view: the Mac has the room,
/// and a Mac user expects the sidebar to stay put.
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
