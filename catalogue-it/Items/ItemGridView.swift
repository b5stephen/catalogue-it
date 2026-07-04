//
//  CatalogueItemGridView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

// MARK: - Item Grid View

struct ItemGridView: View {
    let items: [CatalogueItem]
    let showWishlistBadge: Bool
    @Binding var selectedItem: CatalogueItem?
    @Binding var scrollPosition: ScrollPosition
    let hasMore: Bool
    let isLoadingMore: Bool
    let onLoadMore: () -> Void

#if os(macOS)
    @AppStorage("itemGridCardSize_mac") private var persistedCardSize: Double = Double(AppConstants.GridCardSize.defaultSize)
#else
    @AppStorage("itemGridCardSize_ios") private var persistedCardSize: Double = Double(AppConstants.GridCardSize.defaultSize)
#endif

    // Pinch gesture state — @State only, never @GestureState (see ZoomablePhotoView:
    // @GestureState resets before onEnded fires, causing a one-frame snap-back).
    @State private var isPinching = false
    @State private var pinchStartSize: CGFloat = AppConstants.GridCardSize.defaultSize
    @State private var livePinchSize: CGFloat?

    private var cardSize: CGFloat { livePinchSize ?? CGFloat(persistedCardSize) }
    private var gridColumns: [GridItem] { [GridItem(.adaptive(minimum: cardSize), spacing: 16, alignment: .top)] }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(items) { item in
                    ItemCardView(item: item, showWishlistBadge: showWishlistBadge)
                        .onTapGesture { selectedItem = item }
                        .overlay {
                            if selectedItem == item {
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
            .padding(.vertical)
        }
        .scrollPosition($scrollPosition, anchor: .top)
        .padding(.horizontal, 16)
        .simultaneousGesture(pinchGesture)
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
                persistedCardSize = Double(clamp(pinchStartSize * value.magnification))
                livePinchSize = nil
            }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(AppConstants.GridCardSize.max, max(AppConstants.GridCardSize.min, value))
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
    field.catalogue = catalogue
    container.mainContext.insert(field)

    let item1 = CatalogueItem(isWishlist: false)
    item1.catalogue = catalogue
    container.mainContext.insert(item1)
    let val1 = FieldValue(fieldDefinition: field, fieldType: .text)
    val1.textValue = "Supermarine Spitfire Mk.I"
    val1.item = item1
    container.mainContext.insert(val1)

    let item2 = CatalogueItem(isWishlist: true)
    item2.catalogue = catalogue
    container.mainContext.insert(item2)
    let val2 = FieldValue(fieldDefinition: field, fieldType: .text)
    val2.textValue = "Hawker Hurricane Mk.IIc"
    val2.item = item2
    container.mainContext.insert(val2)

    let item3 = CatalogueItem(isWishlist: false)
    item3.catalogue = catalogue
    container.mainContext.insert(item3)

    return ItemGridView(
        items: [item1, item2, item3],
        showWishlistBadge: true,
        selectedItem: .constant(nil),
        scrollPosition: .constant(ScrollPosition()),
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: {}
    )
    .modelContainer(container)
}
