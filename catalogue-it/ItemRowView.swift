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

    private var fieldSummaries: [(name: String, value: String)] {
        catalogue.fieldDefinitions
            .sorted { $0.sortOrder < $1.sortOrder }
            .prefix(2)
            .compactMap { field in
                guard let fv = item.value(for: field.name),
                      !fv.displayValue.isEmpty else { return nil }
                return (name: field.name, value: fv.displayValue)
            }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
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
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let photo = item.primaryPhoto, let image = makeImage(from: photo.imageData) {
            image
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.15))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
        }
    }

    private func makeImage(from data: Data) -> Image? {
#if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
#elseif os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
#else
        return nil
#endif
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field1 = FieldDefinition(name: "Manufacturer", fieldType: .text, sortOrder: 0)
    field1.catalogue = catalogue
    container.mainContext.insert(field1)

    let field2 = FieldDefinition(name: "Year", fieldType: .number, sortOrder: 1)
    field2.catalogue = catalogue
    container.mainContext.insert(field2)

    let item = CatalogueItem(isWishlist: false)
    item.catalogue = catalogue
    container.mainContext.insert(item)

    let val1 = FieldValue(fieldName: "Manufacturer", fieldType: .text, sortOrder: 0)
    val1.textValue = "Airfix"
    val1.item = item
    container.mainContext.insert(val1)

    let val2 = FieldValue(fieldName: "Year", fieldType: .number, sortOrder: 1)
    val2.numberValue = 1969
    val2.item = item
    container.mainContext.insert(val2)

    return List {
        ItemRowView(item: item, catalogue: catalogue)
    }
    .modelContainer(container)
}
