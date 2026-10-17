//
//  CatalogueSidebar.swift
//  catalogue-it
//

#if !os(macOS)
import SwiftUI
import SwiftData

// MARK: - Catalogue Sidebar (iOS / iPadOS)

/// Rows are `NavigationLink(value:)`s, not `List(selection:)`: the items screen is pushed
/// within this column (see `ContentView`). The link is an invisible sibling behind the card,
/// which avoids a chevron yet keeps the row tappable with swipe actions and reordering intact.
struct CatalogueSidebar: View {
    let catalogues: [Catalogue]
    let onEdit: (Catalogue) -> Void
    let onDelete: (Catalogue) -> Void
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        // Clear row backgrounds hand the whole row rect to the card. `listRowSpacing` rather than
        // insets keeps the swipe buttons flush with the card edges.
        List {
            ForEach(catalogues) { catalogue in
                row(catalogue)
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .listRowSpacing(AppConstants.CatalogueCard.rowSpacing)
        .contentMargins(.vertical, AppConstants.CatalogueCard.rowSpacing, for: .scrollContent)
    }

    @ViewBuilder
    private func row(_ catalogue: Catalogue) -> some View {
        CatalogueCardView(catalogue: catalogue)
            .background {
                NavigationLink(value: catalogue) { EmptyView() }
                    .opacity(0)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: AppConstants.CatalogueCard.horizontalInset,
                    bottom: 0,
                    trailing: AppConstants.CatalogueCard.horizontalInset
                )
            )
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
    }
}
#endif
