//
//  ItemCardView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

// MARK: - Item Card View

struct ItemCardView: View {
    let item: CatalogueItem
    var showWishlistBadge: Bool = false

    private var primaryValue: String {
        guard let catalogue = item.catalogue,
              let first = catalogue.fieldDefinitions.sorted(by: { $0.sortOrder < $1.sortOrder }).first,
              let fv = item.value(for: first),
              !fv.displayValue.isEmpty
        else { return "Untitled Item" }
        return fv.displayValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo or placeholder
            ItemCardPhotoView(photo: item.photos.min(by: { $0.sortOrder < $1.sortOrder }))
                .frame(height: AppConstants.PhotoHeight.card)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if showWishlistBadge && item.isWishlist {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.pink, in: Circle())
                            .padding(6)
                    }
                }

            // Item name
            Text(primaryValue)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(.background)
        .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.medium)
                .stroke(.tertiary, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - Item Card Photo View

private struct ItemCardPhotoView: View {
    let photo: ItemPhoto?

    var body: some View {
        if let photo, let image = photo.imageData.asImage() {
            image
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let item = CatalogueItem(isWishlist: false)
    container.mainContext.insert(item)

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field = FieldDefinition(name: "Name", fieldType: .text, sortOrder: 0)
    field.catalogue = catalogue
    container.mainContext.insert(field)

    item.catalogue = catalogue

    let val = FieldValue(fieldDefinition: field, fieldType: .text)
    val.textValue = "Supermarine Spitfire Mk.I"
    val.item = item
    container.mainContext.insert(val)

    let itemNoName = CatalogueItem(isWishlist: false)
    container.mainContext.insert(itemNoName)

    return ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
            ItemCardView(item: item)
            ItemCardView(item: itemNoName)
        }
        .padding()
    }
    .modelContainer(container)
}
