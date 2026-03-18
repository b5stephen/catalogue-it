//
//  CatalogueItemTableView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 17/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Catalogue Item Table View

struct ItemTableView: View {
    let items: [CatalogueItem]
    let catalogue: Catalogue
    let showWishlistBadge: Bool
    @Binding var selectedItem: CatalogueItem?
    var onViewDetails: ((CatalogueItem) -> Void)? = nil

    private var dynamicFields: [FieldDefinition] {
        Array(
            catalogue.fieldDefinitions
                .sorted { $0.sortOrder < $1.sortOrder }
                .dropFirst()
        )
    }

    // Bridges CatalogueItem? binding to the PersistentIdentifier? that Table requires.
    private var tableSelection: Binding<PersistentIdentifier?> {
        Binding(
            get: { selectedItem?.id },
            set: { id in selectedItem = id.flatMap { id in items.first { $0.id == id } } }
        )
    }

    var body: some View {
        Table(items, selection: tableSelection) {
            // Photo column (fixed width)
            TableColumn("") { item in
                ItemTableThumbnailView(photo: item.primaryPhoto)
                    .frame(width: AppConstants.ThumbnailSize.list,
                           height: AppConstants.ThumbnailSize.list)
                    .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.small))
            }
            .width(AppConstants.ThumbnailSize.list + 16)

            // Name column
            TableColumn("Name") { item in
                Text(item.displayName).lineLimit(1)
#if os(iOS)
                    .contextMenu {
                        if let onViewDetails {
                            Button("View Details", systemImage: "info.circle") {
                                onViewDetails(item)
                            }
                        }
                    }
#endif
            }

            // Dynamic field columns
            TableColumnForEach(dynamicFields) { field in
                TableColumn(field.name) { item in
                    Text(item.value(for: field.name)?.displayValue ?? "")
                        .foregroundStyle(item.value(for: field.name) == nil ? .tertiary : .primary)
                        .lineLimit(1)
                }
            }

            // Optional wishlist column
            if showWishlistBadge {
                TableColumn("") { item in
                    if item.isWishlist {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                            .accessibilityLabel("Wishlist")
                    }
                }
                .width(28)
            }
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { selection in
            if let id = selection.first,
               let item = items.first(where: { $0.id == id }),
               let onViewDetails {
                Button("View Details", systemImage: "info.circle") {
                    onViewDetails(item)
                }
            }
        }
    }
}

// MARK: - Item Table Thumbnail View

private struct ItemTableThumbnailView: View {
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
