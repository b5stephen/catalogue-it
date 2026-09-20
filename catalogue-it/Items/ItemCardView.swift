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
    /// Whether to show the status chip — see `ItemRowView.showStatusChip`.
    var showStatusChip: Bool = false

    private var primaryValue: String {
        // Status and flag fields are rendered as chips/badges, so they never stand in as
        // the item's display name.
        guard let catalogue = item.catalogue,
              let first = catalogue.fieldDefinitions
                  .filter({ $0.displayRole == .none })
                  .sorted(by: FieldDefinition.isOrderedBefore)
                  .first,
              let fv = item.value(for: first),
              !fv.displayValue(options: first.fieldOptions).isEmpty
        else { return "Untitled Item" }
        return fv.displayValue(options: first.fieldOptions)
    }

    private var statusChip: (label: String, tint: Color)? {
        guard showStatusChip,
              let statusField = item.catalogue?.statusField,
              let label = statusField.statusLabel(for: item.statusValue)
        else { return nil }
        return (label, statusField.statusChipTint(for: item.statusValue))
    }

    /// Flags set on this item, capped because a card thumbnail has no room for a long row.
    /// Flags with no icon are dropped before the cap so they don't consume a visible slot.
    private var setFlagFields: [FieldDefinition] {
        guard let catalogue = item.catalogue else { return [] }
        return catalogue.flagFields
            .filter { $0.flagIconName != nil && item.flagKeys.contains(ItemFacetBuilder.flagToken(for: $0.fieldID)) }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo or placeholder
            GeometryReader { geometry in
                ItemCardPhotoView(key: ThumbnailKey(item: item))
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .clipped()
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    ForEach(setFlagFields) { flag in
                        if let icon = flag.flagIconName {
                            Image(systemName: icon)
                                .symbolVariant(.fill)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(flag.flagColor ?? .accentColor, in: Circle())
                                .accessibilityLabel(flag.name)
                        }
                    }
                }
                .padding(6)
            }
            .overlay(alignment: .topLeading) {
                if let chip = statusChip {
                    FieldChipView(text: chip.label, tint: chip.tint)
                        .background(.thinMaterial, in: Capsule())
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
    /// See `ThumbnailKey`: the load re-runs whenever any part of it changes.
    let key: ThumbnailKey
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
        .task(id: key) {
#if os(iOS)
            let itemID = key.itemID
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
            // A load still in flight when the item was saved must not overwrite the fresh
            // thumbnail the save wrote — the re-keyed task will load that one.
            guard !Task.isCancelled else { return }
            if let ui = diskImage {
                await ImageCache.shared.store(ui, for: key)
                loadedImage = Image(uiImage: ui)
                return
            }
            // Tier 3: cold path — each card gets its own ephemeral ModelContext so all
            // visible cards fetch and decode fully in parallel (no shared actor queue).
            guard let container = ThumbnailLoader.container else { loadedImage = nil; return }
            let generated = await Task.detached(priority: .utility) { () -> (data: Data, image: UIImage)? in
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<ItemPhoto>(
                    predicate: #Predicate { $0.item?.persistentModelID == itemID },
                    sortBy: [SortDescriptor(\.priority)]
                )
                descriptor.fetchLimit = 1
                guard let imageData = try? context.fetch(descriptor).first?.imageData,
                      let thumbData = makeThumbnailData(from: imageData),
                      let image = UIImage(data: thumbData)?.preparingForDisplay() else { return nil }
                return (thumbData, image)
            }.value
            // Same guard as above: only a load that is still current may populate the caches.
            guard !Task.isCancelled else { return }
            guard let generated else { loadedImage = nil; return }
            let thumbData = generated.data
            Task.detached(priority: .utility) { ThumbnailLoader.writeThumbnailToCache(thumbData, for: itemID) }
            await ImageCache.shared.store(generated.image, for: key)
            loadedImage = Image(uiImage: generated.image)
#endif
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let item = CatalogueItem()
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

    let itemNoName = CatalogueItem()
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
