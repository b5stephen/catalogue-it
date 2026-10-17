//
//  CatalogueItemListView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI

// MARK: - Item List View

/// A `List`, not a `LazyVStack`, for scroll-position restoration, the accessibility rotor and,
/// on macOS, split-view selection. Its background is hidden: `CatalogueDetailView` draws the
/// ground. `header` is the first row, full-bleed.
struct ItemListView<Header: View>: View {
    let items: [CatalogueItem]
    let catalogue: Catalogue
    let showStatusChip: Bool
    @Binding var selectedItem: CatalogueItem?
    @Binding var scrollPosition: ScrollPosition
    let hasMore: Bool
    let isLoadingMore: Bool
    let onLoadMore: () -> Void
    @ViewBuilder let header: Header

#if !os(macOS)
    @Environment(\.hasDetailColumn) private var hasDetailColumn
#endif

    private var headerRow: some View {
        header
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .selectionDisabled()
    }

    var body: some View {
        // Decoded once here rather than in each of up to 2000+ rows.
        let showPhotos = catalogue.layoutOptions.showPhotosInList
#if !os(macOS)
        // Never `List(selection:)` on iOS: in the split view's leading column it takes the
        // sidebar's filled selection treatment, which reads as a bug over a card.
        List {
            headerRow
            ForEach(items) { item in
                ItemRowView(item: item, catalogue: catalogue, showStatusChip: showStatusChip, showPhoto: showPhotos)
                    .itemCard(in: catalogue, isSelected: hasDetailColumn && selectedItem == item)
                    .onTapGesture { selectedItem = item }
                    .tag(item)
                    .cardRow()
            }
            scrollSentinel
        }
        .listStyle(.plain)
        // The header can be a short spacer; the default minimum would pad it to a row.
        .environment(\.defaultMinListRowHeight, 0)
        .listRowSpacing(AppConstants.ItemCard.rowSpacing)
        .contentMargins(.bottom, AppConstants.ItemCard.rowSpacing, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollPosition($scrollPosition, anchor: .top)
#else
        regularList(showPhotos: showPhotos)
#endif
    }

    private func regularList(showPhotos: Bool) -> some View {
        List(selection: $selectedItem) {
            headerRow
            ForEach(items) { item in
                ItemRowView(item: item, catalogue: catalogue, showStatusChip: showStatusChip, showPhoto: showPhotos)
                    .itemCard(in: catalogue, isSelected: selectedItem == item)
                    .tag(item)
                    .cardRow()
            }
            scrollSentinel
        }
        .listStyle(.plain)
        // The header can be a short spacer; the default minimum would pad it to a row.
        .environment(\.defaultMinListRowHeight, 0)
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
    /// Gaps come from `listRowSpacing`: vertical insets would inflate the row rect.
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
