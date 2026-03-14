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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo or placeholder
            ItemCardPhotoView(photo: item.primaryPhoto)
                .frame(height: 150)
                .clipped()

            // Item name
            Text(item.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(.background)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
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
                .fill(Color.secondary.opacity(0.15))
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(Color.secondary.opacity(0.6))
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

    let val = FieldValue(fieldName: "Name", fieldType: .text, sortOrder: 0)
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
