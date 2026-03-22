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
    let gridColumns: [GridItem]
    let showWishlistBadge: Bool
    @Binding var selectedItem: CatalogueItem?

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
            }
            .padding(.vertical)
        }
        .padding(.horizontal, 16)
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

    let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    return ItemGridView(
        items: [item1, item2, item3],
        gridColumns: columns,
        showWishlistBadge: true,
        selectedItem: .constant(nil)
    )
    .modelContainer(container)
}
