//
//  CatalogueSidebar.swift
//  catalogue-it
//

#if !os(macOS)
import SwiftUI
import SwiftData

// MARK: - Catalogue Sidebar (iOS / iPadOS)

/// The catalogue list as it appears in the leading column on iPhone and iPad: full-colour
/// cards that push their catalogue's items onto the column's `NavigationStack`.
///
/// Rows are `NavigationLink(value:)`s rather than a `List(selection:)`, because the items
/// screen is pushed *within* this column, not shown beside it — see `ContentView` for why the
/// split view is two columns here. The link is an invisible sibling behind the card: a visible
/// link draws a disclosure chevron that has nowhere sensible to sit on a card, and a hidden one
/// still makes the whole row tappable while leaving swipe actions and drag reordering intact.
struct CatalogueSidebar: View {
    let catalogues: [Catalogue]
    let onEdit: (Catalogue) -> Void
    let onDelete: (Catalogue) -> Void
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        // Cards, not a tied-together list: a plain list plus clear row backgrounds hands the
        // whole row rect to `CatalogueCardView`, while the list keeps swipe actions and drag
        // reordering. `listRowSpacing` (rather than vertical row insets) puts the gap *between*
        // rows, so the swipe buttons stay flush with the card edges.
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
