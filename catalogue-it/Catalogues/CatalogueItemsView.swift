//
//  CatalogueItemsView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/03/2026.
//

import SwiftUI
import SwiftData

/// `header` is the first thing in the scroll content, typically a spacer under whatever the
/// caller floats over the list; the scroll is reported through `scrollState` so it can collapse.
struct CatalogueItemsView<Header: View>: View {
    let catalogue: Catalogue
    let statusTab: StatusTab
    let activeFlagIDs: [UUID]
    let searchText: String
    @Binding var sortFieldKey: String
    @Binding var sortDirection: String
    @Binding var selectedItem: CatalogueItem?
    @Binding var displayedCount: Int
    /// `displayedCount` without the flag filters.
    @Binding var unflaggedCount: Int
    let scrollState: BandScrollState
    /// Scrolling past this is of no interest to `scrollState`'s reader; zero stops the reports.
    let trackedScrollRange: CGFloat
    let selection: ItemSelectionState
    @ViewBuilder let header: Header

    @Environment(\.modelContext) private var modelContext
    @State private var pagination = ItemPaginationController()
    @State private var scrollPosition = ScrollPosition()
    // The most recently tapped item, to restore the scroll position after a force reset.
    @State private var scrollAnchorID: PersistentIdentifier?
    @State private var itemToEdit: CatalogueItem?
    @State private var itemToDuplicate: CatalogueItem?
    @State private var itemToShare: CatalogueItem?
    @State private var itemToDelete: CatalogueItem?
    @State private var shareRequest: ExportRequest?
    @State private var showingDeleteConfirmation = false

    private var filterFingerprint: FilterFingerprint {
        FilterFingerprint(
            catalogueID: catalogue.persistentModelID,
            statusTab: statusTab,
            activeFlagIDs: activeFlagIDs,
            searchText: searchText,
            sortFieldKey: sortFieldKey,
            sortDirection: sortDirection
        )
    }

    var body: some View {
        Group {
            if pagination.items.isEmpty && !pagination.isLoadingMore {
                // In a scroll view like the lists it stands in for: bare, a landscape iPhone spun forever
                // laying out the push, re-resolving the bars against the band's spacer. At least the
                // visible height, so the message centres in what the header leaves.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            header
                            CatalogueEmptyStateView(
                                catalogue: catalogue,
                                statusTab: statusTab,
                                hasActiveFlags: !activeFlagIDs.isEmpty,
                                isFiltered: !searchText.isEmpty && pagination.hasAnyItems
                            )
                        }
                        .frame(minHeight: proxy.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                switch catalogue.itemLayout {
                case .grid:
                    ItemGridView(
                        items: pagination.items,
                        showStatusChip: statusTab == .all,
                        catalogue: catalogue,
                        selectedItem: $selectedItem,
                        scrollPosition: $scrollPosition,
                        hasMore: pagination.hasMore,
                        isLoadingMore: pagination.isLoadingMore,
                        onLoadMore: { pagination.loadMore(context: modelContext) },
                        actions: cardActions,
                        selection: selection,
                        header: { header }
                    )
                case .list:
                    ItemListView(
                        items: pagination.items,
                        catalogue: catalogue,
                        showStatusChip: statusTab == .all,
                        selectedItem: $selectedItem,
                        scrollPosition: $scrollPosition,
                        hasMore: pagination.hasMore,
                        isLoadingMore: pagination.isLoadingMore,
                        onLoadMore: { pagination.loadMore(context: modelContext) },
                        actions: cardActions,
                        selection: selection,
                        header: { header }
                    )
                }
            }
        }
        // Clamped, so the action stops firing past the range. It hears every scroll view beneath,
        // so the cards mustn't contain one: a horizontal one would report zero and snap the
        // caller's view back open.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            min(max(geometry.contentOffset.y + geometry.contentInsets.top, 0), trackedScrollRange)
        } action: { _, offset in
            scrollState.offset = offset
        }
        .task {
            pagination.reset(fingerprint: filterFingerprint, context: modelContext)
        }
        .onAppear {
            let didReset = pagination.startObservingStoreChanges()
            if didReset, let anchorID = scrollAnchorID {
                // A save happened behind a push and the list reloaded from page 1: load pages until the
                // edited item is back, then scroll to it.
                while !pagination.items.contains(where: { $0.persistentModelID == anchorID }),
                      pagination.hasMore {
                    pagination.loadMore(context: modelContext)
                }
                scrollPosition = ScrollPosition(id: anchorID)
                scrollAnchorID = nil
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            if let item = newItem {
                scrollAnchorID = item.persistentModelID
            }
        }
        .onChange(of: filterFingerprint) {
            selection.follow(filterFingerprint)
            scrollAnchorID = nil
            scrollPosition = ScrollPosition(edge: .top)
            // The empty state never scrolls, so it would never report the top back.
            scrollState.offset = 0
            pagination.reset(fingerprint: filterFingerprint, context: modelContext)
        }
        .onChange(of: pagination.totalCount) {
            displayedCount = pagination.totalCount
        }
        .onChange(of: pagination.unflaggedCount) {
            unflaggedCount = pagination.unflaggedCount
        }
        .onDisappear {
            pagination.stopObservingStoreChanges()
        }
        .sheet(item: $itemToEdit) { item in
            AddEditItemView(catalogue: catalogue, item: item)
                .catalogueTint(catalogue)
        }
        .sheet(item: $itemToDuplicate) { item in
            AddEditItemView(catalogue: catalogue, duplicateSource: item)
                .catalogueTint(catalogue)
        }
        .sheet(item: $itemToShare) { item in
            ExportComposerView(catalogue: catalogue, item: item)
                .catalogueTint(catalogue)
        }
        .sheet(item: $shareRequest) { request in
            ExportComposerView(catalogue: catalogue, request: request)
                .catalogueTint(catalogue)
        }
        .toolbar {
            if selection.isSelecting {
                selectionBar
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will be moved to Recently Deleted.")
        }
        .overlay {
            if selection.showsProgress, let progress = selection.progress {
                ProgressOverlay(
                    current: progress.done,
                    total: progress.total,
                    preparingText: "Preparing…",
                    processingText: { current, total in "Processing \(current) of \(total) items…" }
                )
            }
        }
        .confirmationDialog(
            itemToDelete.map(itemDeleteTitle) ?? "",
            isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }),
            titleVisibility: .visible,
            presenting: itemToDelete
        ) { item in
            Button("Delete", role: .destructive) { softDelete(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The item will be moved to Recently Deleted.")
        }
    }

    private func itemDeleteTitle(_ item: CatalogueItem) -> String {
        let name = catalogue.sortedFieldDefinitions.first.map { item.displayValue(for: $0) } ?? ""
        return String(localized: "Delete \"\(name.isEmpty ? String(localized: "Untitled Item") : name)\"?")
    }

    // MARK: - Selection

    private var selectedCount: Int {
        selection.count(totalMatching: pagination.totalCount)
    }

    private var deleteTitle: LocalizedStringKey {
        selectedCount == 1 ? "Delete 1 Item?" : "Delete \(selectedCount) Items?"
    }

    /// The search field stays between the buttons, so filtering works while selecting.
    @ToolbarContentBuilder
    private var selectionBar: some ToolbarContent {
        let isDisabled = selectedCount == 0 || selection.isWorking
        ToolbarItem(placement: .bottomBar) {
            Button("Share", systemImage: "square.and.arrow.up") { shareSelection() }
                .accessibilityIdentifier("selectionShareButton")
                .disabled(isDisabled)
        }
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button("Delete", systemImage: "trash", role: .destructive) { showingDeleteConfirmation = true }
                .accessibilityIdentifier("selectionDeleteButton")
                .disabled(isDisabled)
        }
    }

    private func shareSelection() {
        Task {
            shareRequest = await selection.prepareExport(
                container: modelContext.container,
                context: modelContext,
                current: filterFingerprint
            )
        }
    }

    private func deleteSelection() {
        let container = modelContext.container
        let fingerprint = filterFingerprint
        Task {
            let ids = await selection.resolve(container: container, current: fingerprint)
            guard !ids.isEmpty else { return }
            if let current = selectedItem, ids.contains(current.persistentModelID) {
                selectedItem = nil
            }
            if await selection.softDelete(ids, container: container) {
                selection.end()
            }
        }
    }

    // MARK: - Card Actions

    private var cardActions: ItemCardActions {
        ItemCardActions(
            edit: { itemToEdit = $0 },
            duplicate: { itemToDuplicate = $0 },
            share: { itemToShare = $0 },
            delete: { itemToDelete = $0 }
        )
    }

    /// Saved at once: the list reloads on a save, so the row would otherwise linger until autosave.
    private func softDelete(_ item: CatalogueItem) {
        if selectedItem == item {
            selectedItem = nil
        }
        item.deletedDate = Date.now
        try? modelContext.save()
    }
}
