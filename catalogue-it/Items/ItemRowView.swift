//
//  ItemRowView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

// MARK: - Item Row View

struct ItemRowView: View {
    let item: CatalogueItem
    let catalogue: Catalogue
    /// Whether to show the status chip. Suppressed when the list is already filtered to a
    /// single status — every row would carry the same chip, which is noise.
    var showStatusChip: Bool = false
    /// `catalogue.layoutOptions.showPhotosInList`, decoded once by the list rather than once
    /// per row.
    var showPhoto: Bool = true

    private var sortedFields: [FieldDefinition] {
        catalogue.sortedFieldDefinitions
    }

    /// Status fields are surfaced as a chip and flags as badges, so repeating them in the
    /// summary lines would say the same thing twice.
    private var summaryFields: [FieldDefinition] {
        sortedFields.filter { $0.displayRole == .none }
    }

    private var statusChip: (label: String, tint: Color)? {
        guard showStatusChip, let statusField = catalogue.statusField,
              let label = statusField.statusLabel(for: item.statusValue)
        else { return nil }
        return (label, statusField.statusChipTint(for: item.statusValue))
    }

    private var setFlagFields: [FieldDefinition] {
        catalogue.flagFields.filter { item.flagKeys.contains(ItemFacetBuilder.flagToken(for: $0.fieldID)) }
    }

    private var primaryValue: String {
        guard let first = summaryFields.first,
              let fv = item.value(for: first),
              !fv.displayValue(options: first.fieldOptions).isEmpty
        else { return "Untitled Item" }
        return fv.displayValue(options: first.fieldOptions)
    }

    private var fieldSummaries: [(name: String, value: String)] {
        summaryFields
            .dropFirst()
            .prefix(2)
            .compactMap { field in
                guard let fv = item.value(for: field),
                      !fv.displayValue(options: field.fieldOptions).isEmpty else { return nil }
                return (name: field.name, value: fv.displayValue(options: field.fieldOptions))
            }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail — radius derived from the card's, so its corners run parallel to the
            // card's corners (see `AppConstants.ItemCard.thumbnailCornerRadius`).
            if showPhoto {
                ItemThumbnailView(key: ThumbnailKey(item: item))
                    .frame(width: AppConstants.ThumbnailSize.list, height: AppConstants.ThumbnailSize.list)
                    .clipShape(.rect(cornerRadius: AppConstants.ItemCard.thumbnailCornerRadius, style: .continuous))
            }

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryValue)
                    .font(.headline)
                    .lineLimit(1)

                ForEach(fieldSummaries, id: \.name) { summary in
                    Text("\(summary.name): \(summary.value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // The thumbnail is what gives the row its floor — an item with one summary line
            // is as tall as one with three. Keep that floor when the photo is off, so the
            // rows stay one height whichever way the catalogue is set, and pin the text to
            // the top so the title sits on the same line in every row, however many summary
            // lines follow it.
            .frame(minHeight: AppConstants.ThumbnailSize.list, alignment: .topLeading)

            Spacer(minLength: 0)

            // Flags sit inboard of the status chip so the chip is always the last element
            // in the row. Its trailing edge then lines up down the whole list, however many
            // flags each item happens to carry.
            ForEach(setFlagFields) { flag in
                if let icon = flag.flagIconName {
                    Image(systemName: icon)
                        .symbolVariant(.fill)
                        .foregroundStyle(flag.flagColor ?? .accentColor)
                        .font(.caption)
                        .accessibilityLabel(flag.name)
                }
            }

            if let chip = statusChip {
                FieldChipView(text: chip.label, tint: chip.tint)
            }
        }
        .accessibilityIdentifier("item-\(primaryValue)")
    }
}

// MARK: - Item Thumbnail View

private struct ItemThumbnailView: View {
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
                // The row clips to the tile shape, so the placeholder needs no corners of its own.
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
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
            // Tier 2: filesystem cache — off the actor so all visible rows read in parallel.
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
            // Tier 3: cold path — each row gets its own ephemeral ModelContext so all
            // visible rows fetch and decode fully in parallel (no shared actor queue).
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

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field1 = FieldDefinition(name: "Manufacturer", fieldType: .text, priority: 0)
    field1.catalogue = catalogue
    container.mainContext.insert(field1)

    let field2 = FieldDefinition(name: "Year", fieldType: .number, priority: 1)
    field2.catalogue = catalogue
    container.mainContext.insert(field2)

    let item = CatalogueItem()
    item.catalogue = catalogue
    container.mainContext.insert(item)

    let val1 = FieldValue(fieldDefinition: field1, fieldType: .text)
    val1.textValue = "Airfix"
    val1.item = item
    container.mainContext.insert(val1)

    let val2 = FieldValue(fieldDefinition: field2, fieldType: .number)
    val2.numberValue = 1969
    val2.item = item
    container.mainContext.insert(val2)

    return List {
        ItemRowView(item: item, catalogue: catalogue)
    }
    .modelContainer(container)
}
