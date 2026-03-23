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
    var showWishlistBadge: Bool = false

    private var sortedFields: [FieldDefinition] {
        catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
    }

    private var primaryValue: String {
        guard let first = sortedFields.first,
              let fv = item.value(for: first),
              !fv.displayValue(numberOptions: first.numberOptions).isEmpty
        else { return "Untitled Item" }
        return fv.displayValue(numberOptions: first.numberOptions)
    }

    private var fieldSummaries: [(name: String, value: String)] {
        sortedFields
            .dropFirst()
            .prefix(2)
            .compactMap { field in
                guard let fv = item.value(for: field),
                      !fv.displayValue(numberOptions: field.numberOptions).isEmpty else { return nil }
                return (name: field.name, value: fv.displayValue(numberOptions: field.numberOptions))
            }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ItemThumbnailView(photo: item.photos.min(by: { $0.priority < $1.priority }))
                .frame(width: AppConstants.ThumbnailSize.list, height: AppConstants.ThumbnailSize.list)
                .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.small))

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

            Spacer(minLength: 0)

            if showWishlistBadge && item.isWishlist {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("item-\(primaryValue)")
    }
}

// MARK: - Item Thumbnail View

private struct ItemThumbnailView: View {
    let photo: ItemPhoto?

    var body: some View {
        if let photo, let image = photo.imageData.asImage() {
            image
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.small)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "photo")
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

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field1 = FieldDefinition(name: "Manufacturer", fieldType: .text, priority: 0)
    field1.catalogue = catalogue
    container.mainContext.insert(field1)

    let field2 = FieldDefinition(name: "Year", fieldType: .number, priority: 1)
    field2.catalogue = catalogue
    container.mainContext.insert(field2)

    let item = CatalogueItem(isWishlist: false)
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
