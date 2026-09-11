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
/// free. The card look is a clear row background plus `listRowSpacing`; the ground it sits on
/// is drawn by `CatalogueDetailView`, which is why the list's own background is hidden here.
///
/// `header` is the first row: full-bleed, and spaced from the first card by the same gap
/// the cards keep between themselves. `pinnedHeader` sits between it and the cards, and
/// stays put once it reaches the top — a plain list's section headers do that on their own.
struct ItemListView<Header: View, PinnedHeader: View>: View {
    let items: [CatalogueItem]
    let catalogue: Catalogue
    let showStatusChip: Bool
    @Binding var selectedItem: CatalogueItem?
    @Binding var scrollPosition: ScrollPosition
    let hasMore: Bool
    let isLoadingMore: Bool
    let onLoadMore: () -> Void
    @ViewBuilder let header: Header
    @ViewBuilder let pinnedHeader: PinnedHeader

#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var headerRow: some View {
        header
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .selectionDisabled()
    }

    private var pinnedHeaderRow: some View {
        pinnedHeader
            .listRowInsets(EdgeInsets())
            .listSectionSeparator(.hidden)
    }

    var body: some View {
#if !os(macOS)
        if horizontalSizeClass == .compact {
            List {
                headerRow
                Section {
                    ForEach(items) { item in
                        ItemRowView(item: item, catalogue: catalogue, showStatusChip: showStatusChip)
                            .itemCard(in: catalogue)
                            .onTapGesture { selectedItem = item }
                            .tag(item)
                            .cardRow()
                    }
                    scrollSentinel
                } header: {
                    pinnedHeaderRow
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .listRowSpacing(AppConstants.ItemCard.rowSpacing)
            .contentMargins(.bottom, AppConstants.ItemCard.rowSpacing, for: .scrollContent)
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
            headerRow
            Section {
                ForEach(items) { item in
                    ItemRowView(item: item, catalogue: catalogue, showStatusChip: showStatusChip)
                        .itemCard(in: catalogue, isSelected: selectedItem == item)
                        .tag(item)
                        .cardRow()
                }
                scrollSentinel
            } header: {
                pinnedHeaderRow
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .listRowSpacing(AppConstants.ItemCard.rowSpacing)
        .contentMargins(.bottom, AppConstants.ItemCard.rowSpacing, for: .scrollContent)
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
