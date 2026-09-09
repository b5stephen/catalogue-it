//
//  CatalogueCardView.swift
//  catalogue-it
//

import SwiftUI
import SwiftData

// MARK: - Catalogue Card View

/// A catalogue as a standalone card on the My Catalogues screen.
///
/// Still rendered as a `List` row rather than in a `LazyVStack`: `swipeActions` is a
/// `List`-only modifier, and staying in a list also keeps `onMove` reordering, split-view
/// selection and the VoiceOver action rotor for free. The card look comes from a clear
/// `listRowBackground` plus `listRowSpacing` — see `ContentView.catalogueRow`. Using
/// `listRowSpacing` for the gaps rather than vertical `listRowInsets` matters: insets would
/// inflate the row rect and leave the swipe buttons standing taller than the card.
///
/// Because the row background is clear, the system selection highlight no longer draws, so
/// selection is carried by the card's own tint and border.
struct CatalogueCardView: View {
    @Environment(\.modelContext) private var modelContext
    let catalogue: Catalogue
    /// Drives the selected appearance. It only really shows in regular width, where the split
    /// view keeps a catalogue selected alongside its items; in compact width the detail screen
    /// covers the list anyway.
    var isSelected: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
    }

    private var itemCount: Int {
        CatalogueSummary.itemCount(for: catalogue, in: modelContext)
    }

    var body: some View {
        let count = itemCount

        HStack(spacing: 14) {
            iconTile

            VStack(alignment: .leading, spacing: 6) {
                Text(catalogue.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(count == 1 ? "1 item" : "\(count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(AppConstants.CatalogueCard.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A wash of the catalogue's colour over a neutral base, rather than a flat colour fill:
        // the colour is the user's to pick, and a light wash keeps the name legible against any
        // of them in both light and dark appearance.
        .background {
            shape
                .fill(.background.secondary)
                .overlay { shape.fill(catalogue.color.opacity(isSelected ? 0.20 : 0.10)) }
                .overlay {
                    shape.strokeBorder(
                        catalogue.color.opacity(isSelected ? 0.85 : 0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
                }
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("catalogue-\(catalogue.name)")
    }

    private var iconTile: some View {
        CatalogueIconView(iconName: catalogue.iconName, color: catalogue.color, size: 28)
            .frame(
                width: AppConstants.CatalogueCard.iconTile,
                height: AppConstants.CatalogueCard.iconTile
            )
            .background(
                catalogue.color.opacity(0.18),
                in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.medium, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
