//
//  CatalogueItemListView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI

// MARK: - Item List View

/// Still a `List` rather than a `LazyVStack`, for the same reasons as the catalogue cards:
/// split-view selection, `scrollPosition` restoration and the accessibility rotor come for
/// free. The card look is a clear row background plus `listRowSpacing`; the wash it sits on
/// is drawn by `CatalogueDetailView`, which is why the list's own background is hidden here.
struct ItemListView: View {
    let items: [CatalogueItem]
    let catalogue: Catalogue
    let showStatusChip: Bool
    @Binding var selectedItem: CatalogueItem?
    @Binding var scrollPosition: ScrollPosition
    let hasMore: Bool
    let isLoadingMore: Bool
    let onLoadMore: () -> Void

#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
#if !os(macOS)
        if horizontalSizeClass == .compact {
            List {
                ForEach(items) { item in
                    ItemRowView(item: item, catalogue: catalogue, showStatusChip: showStatusChip)
                        .itemCard()
                        .onTapGesture { selectedItem = item }
                        .tag(item)
                        .cardRow()
                }
                scrollSentinel
            }
            .listStyle(.plain)
            .listRowSpacing(AppConstants.ItemCard.rowSpacing)
            .contentMargins(.vertical, AppConstants.ItemCard.rowSpacing, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .scrollPosition($scrollPosition, anchor: .top)
        } else {
            regularList
        }
#else
        regularList
#endif
    }

    private var regularList: some View {
        List(selection: $selectedItem) {
            ForEach(items) { item in
                ItemRowView(item: item, catalogue: catalogue, showStatusChip: showStatusChip)
                    .itemCard(isSelected: selectedItem == item)
                    .tag(item)
                    .cardRow()
            }
            scrollSentinel
        }
        .listStyle(.plain)
        .listRowSpacing(AppConstants.ItemCard.rowSpacing)
        .contentMargins(.vertical, AppConstants.ItemCard.rowSpacing, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollPosition($scrollPosition, anchor: .top)
    }

    @ViewBuilder
    private var scrollSentinel: some View {
        if hasMore {
            Color.clear
                .frame(height: 1)
                .cardRow()
                .onAppear { onLoadMore() }
        }
        if isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .cardRow()
                .padding()
        }
    }
}

private extension View {
    /// Strips a `List` row back to nothing but its content, so the card draws its own
    /// background and the gaps between cards come from `listRowSpacing`. Spacing rather than
    /// vertical insets, as on the Catalogues screen: insets would inflate the row rect.
    func cardRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: AppConstants.ItemCard.horizontalInset,
                    bottom: 0,
                    trailing: AppConstants.ItemCard.horizontalInset
                )
            )
    }
}
