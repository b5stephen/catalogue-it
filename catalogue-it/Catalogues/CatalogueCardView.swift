//
//  CatalogueCardView.swift
//  catalogue-it
//

import SwiftUI
import SwiftData

// MARK: - Catalogue Card View

/// A `List` row, not a `LazyVStack` child, for `swipeActions`, `onMove` and the VoiceOver
/// rotor. Gaps come from `listRowSpacing`, not insets, which would leave the swipe buttons
/// taller than the card. The clear row background hides the system highlight, and the card is
/// already coloured, so selection is an inset ring in its foreground colour. Nothing keeps a
/// catalogue selected in the app today; `isSelected` serves the preview.
struct CatalogueCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let catalogue: Catalogue
    var isSelected: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
    }

    private var itemCount: Int {
        CatalogueSummary.itemCount(for: catalogue, in: modelContext)
    }

    var body: some View {
        let count = itemCount
        let palette = catalogue.palette(
            for: colorScheme,
            isSelected: isSelected,
            increasedContrast: colorSchemeContrast == .increased
        )

        HStack(spacing: 14) {
            iconTile(palette)

            VStack(alignment: .leading, spacing: 6) {
                Text(catalogue.name)
                    .font(.headline)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)

                Text(count == 1 ? "1 item" : "\(count) items")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(AppConstants.CatalogueCard.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Duotone — see `CataloguePalette`. The neutral base matters for near-grey catalogues and
        // keeps the corners from showing through during the insert animation.
        .background {
            shape
                .fill(.background.secondary)
                .overlay { shape.fill(palette.fill) }
                .overlay {
                    // Inset, so a selected card isn't a different size from its neighbours.
                    shape
                        .inset(by: palette.isSelected ? 2 : 0)
                        .strokeBorder(palette.border, lineWidth: palette.borderWidth)
                }
                .compositingGroup()
                .shadow(color: palette.shadow, radius: palette.shadowRadius, y: 3)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("catalogue-\(catalogue.name)")
    }

    /// Translucent rather than a colour, so it reads anywhere on the ramp.
    private func iconTile(_ palette: CataloguePalette) -> some View {
        CatalogueIconView(iconName: catalogue.iconName, color: palette.iconGlyph, size: 28)
            .frame(
                width: AppConstants.CatalogueCard.iconTile,
                height: AppConstants.CatalogueCard.iconTile
            )
            .background(
                palette.iconTint,
                in: RoundedRectangle(cornerRadius: AppConstants.CatalogueCard.iconTileCornerRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

/// Picks that each failed in one appearance: mid blue, navy and maroon (dark), pale yellow
/// (light), and a near-grey that must stay grey.
private struct CatalogueCardGallery: View {
    let catalogues: [Catalogue]

    var body: some View {
        List {
            ForEach(Array(catalogues.enumerated()), id: \.offset) { index, catalogue in
                CatalogueCardView(catalogue: catalogue, isSelected: index == 0)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: AppConstants.CatalogueCard.horizontalInset,
                            bottom: 0,
                            trailing: AppConstants.CatalogueCard.horizontalInset
                        )
                    )
            }
        }
        .listStyle(.plain)
        .listRowSpacing(AppConstants.CatalogueCard.rowSpacing)
    }
}

@MainActor
private func previewCatalogues() -> (ModelContainer, [Catalogue]) {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let specs: [(String, String, String)] = [
        ("Model Planes", "airplane", "#007AFF"),
        ("First Editions", "books.vertical", "#1B2A5E"),
        ("Vintage Wine", "wineglass", "#5C1A22"),
        ("Field Notes", "note.text", "#F5E6A8"),
        ("Archive", "🗂️", "#8A8A8E")
    ]

    let catalogues = specs.map { name, icon, hex in
        let catalogue = Catalogue(name: name, iconName: icon, colorHex: hex)
        container.mainContext.insert(catalogue)
        return catalogue
    }

    return (container, catalogues)
}

#Preview("Catalogue cards") {
    let (container, catalogues) = previewCatalogues()
    CatalogueCardGallery(catalogues: catalogues)
        .modelContainer(container)
}
