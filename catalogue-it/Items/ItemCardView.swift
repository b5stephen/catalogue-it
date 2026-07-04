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
    var cardSize: CGFloat = AppConstants.GridCardSize.defaultSize
    var showWishlistBadge: Bool = false

    private var photoHeight: CGFloat {
        cardSize * AppConstants.GridCardSize.photoAspectRatio
    }

    private var primaryValue: String {
        guard let catalogue = item.catalogue,
              let first = catalogue.fieldDefinitions.sorted(by: { $0.priority < $1.priority }).first,
              let fv = item.value(for: first),
              !fv.displayValue(options: first.fieldOptions).isEmpty
        else { return "Untitled Item" }
        return fv.displayValue(options: first.fieldOptions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo or placeholder
            ItemCardPhotoView(itemID: item.persistentModelID)
                .frame(height: photoHeight)
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
    let itemID: PersistentIdentifier
    @State private var loadedImage: Image?

    var body: some View {
        Group {
            if let loadedImage {
                loadedImage
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
        .task(id: itemID) {
#if os(iOS)
            let key = "cover_\(itemID)"
            // Tier 1: in-memory cache — synchronous, no I/O.
            if let cached = await ImageCache.shared.image(for: key) {
                loadedImage = Image(uiImage: cached)
                return
            }
            // Tier 2: filesystem cache — off the actor so all visible cards read in parallel.
            // preparingForDisplay() forces JPEG pixel-decode here off the main thread.
            let diskImage = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let url = ThumbnailLoader.thumbnailCacheURL(for: itemID),
                      let data = try? Data(contentsOf: url),
                      let img = UIImage(data: data) else { return nil }
                return img.preparingForDisplay()
            }.value
            if let ui = diskImage {
                await ImageCache.shared.store(ui, for: key)
                loadedImage = Image(uiImage: ui)
                return
            }
            // Tier 3: cold path — each card gets its own ephemeral ModelContext so all
            // visible cards fetch and decode fully in parallel (no shared actor queue).
            guard let container = ThumbnailLoader.container else { loadedImage = nil; return }
            let ui = await Task.detached(priority: .utility) { () -> UIImage? in
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<ItemPhoto>(
                    predicate: #Predicate { $0.item?.persistentModelID == itemID },
                    sortBy: [SortDescriptor(\.priority)]
                )
                descriptor.fetchLimit = 1
                guard let imageData = try? context.fetch(descriptor).first?.imageData,
                      let thumbData = makeThumbnailData(from: imageData) else { return nil }
                ThumbnailLoader.writeThumbnailToCache(thumbData, for: itemID)
                return UIImage(data: thumbData)?.preparingForDisplay()
            }.value
            guard let ui else { loadedImage = nil; return }
            await ImageCache.shared.store(ui, for: key)
            loadedImage = Image(uiImage: ui)
#endif
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

    let field = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
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
