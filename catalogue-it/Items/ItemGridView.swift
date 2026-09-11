//
//  CatalogueItemGridView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

// MARK: - Item Grid View

struct ItemGridView<Header: View, PinnedHeader: View>: View {
    let items: [CatalogueItem]
    let showStatusChip: Bool
    @Bindable var catalogue: Catalogue
    @Binding var selectedItem: CatalogueItem?
    @Binding var scrollPosition: ScrollPosition
    let hasMore: Bool
    let isLoadingMore: Bool
    let onLoadMore: () -> Void
    /// Scrolls with the grid, above it, full-bleed.
    @ViewBuilder let header: Header
    /// Below `header`; sticks to the top once it gets there.
    @ViewBuilder let pinnedHeader: PinnedHeader

#if !os(macOS)
    // On compact width, selecting an item pushes ItemDetailView via the same
    // `selectedItem` binding, so the border would flash for a frame before the
    // push transition covers it. Only show it where selection persists on-screen
    // (regular width split view / macOS detail column).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var showsSelectionBorder: Bool { horizontalSizeClass != .compact }
#else
    private let showsSelectionBorder = true
#endif

    // Pinch gesture state — @State only, never @GestureState (see ZoomablePhotoView:
    // @GestureState resets before onEnded fires, causing a one-frame snap-back).
    @State private var isPinching = false
    @State private var pinchStartSize: CGFloat = AppConstants.GridCardSize.defaultSize
    @State private var livePinchSize: CGFloat?

    private var cardSize: CGFloat { livePinchSize ?? CGFloat(catalogue.gridCardSize) }
    private var gridColumns: [GridItem] { [GridItem(.adaptive(minimum: cardSize), spacing: 16, alignment: .top)] }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                header
                Section {
                    grid
                } header: {
                    pinnedHeader
                }
            }
        }
        .scrollPosition($scrollPosition, anchor: .top)
        .simultaneousGesture(pinchGesture)
    }

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(items) { item in
                ItemCardView(item: item, showStatusChip: showStatusChip)
                    .onTapGesture { selectedItem = item }
                    .overlay {
                        if showsSelectionBorder && selectedItem == item {
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.medium)
                                .strokeBorder(.tint, lineWidth: 2.5)
                        }
                    }
            }
            if hasMore {
                Color.clear
                    .frame(height: 1)
                    .onAppear { onLoadMore() }
            }
            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .gridCellColumns(gridColumns.count)
            }
        }
        // Top clearance comes from the header above, the same as the list's.
        .padding(.bottom)
        .padding(.horizontal, 16)
    }

    // MARK: - Gesture

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    pinchStartSize = cardSize
                }
                livePinchSize = clamp(pinchStartSize * value.magnification)
            }
            .onEnded { value in
                isPinching = false
                catalogue.gridCardSize = Double(clamp(pinchStartSize * value.magnification))
                livePinchSize = nil
            }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(AppConstants.GridCardSize.max, max(AppConstants.GridCardSize.min, value))
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
    field.catalogue = catalogue
    container.mainContext.insert(field)

    let item1 = CatalogueItem()
    item1.catalogue = catalogue
    container.mainContext.insert(item1)
    let val1 = FieldValue(fieldDefinition: field, fieldType: .text)
    val1.textValue = "Supermarine Spitfire Mk.I"
    val1.item = item1
    container.mainContext.insert(val1)

    let item2 = CatalogueItem()
    item2.catalogue = catalogue
    container.mainContext.insert(item2)
    let val2 = FieldValue(fieldDefinition: field, fieldType: .text)
    val2.textValue = "Hawker Hurricane Mk.IIc"
    val2.item = item2
    container.mainContext.insert(val2)

    let item3 = CatalogueItem()
    item3.catalogue = catalogue
    container.mainContext.insert(item3)

    return ItemGridView(
        items: [item1, item2, item3],
        showStatusChip: true,
        catalogue: catalogue,
        selectedItem: .constant(nil),
        scrollPosition: .constant(ScrollPosition()),
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: {},
        header: { Text("Model Planes").font(.title2.bold()).padding() },
        pinnedHeader: { Text("Tabs").padding() }
    )
    .modelContainer(container)
}
