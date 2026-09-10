//
//  CatalogueCardView.swift
//  catalogue-it
//

import SwiftUI
import SwiftData

// MARK: - Catalogue Card View

/// A catalogue as a standalone card on the Catalogues screen.
///
/// Still rendered as a `List` row rather than in a `LazyVStack`: `swipeActions` is a
/// `List`-only modifier, and staying in a list also keeps `onMove` reordering, split-view
/// selection and the VoiceOver action rotor for free. The card look comes from a clear
/// `listRowBackground` plus `listRowSpacing` — see `ContentView.catalogueRow`. Using
/// `listRowSpacing` for the gaps rather than vertical `listRowInsets` matters: insets would
/// inflate the row rect and leave the swipe buttons standing taller than the card.
///
/// Because the row background is clear, the system selection highlight no longer draws. The
/// card can't signal selection by becoming coloured either — it already is — so selection is an
/// inset ring in the card's own foreground colour, which reads on any fill.
struct CatalogueCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
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
        // The accent is the card, as a duotone gradient — see `CataloguePalette`. The neutral
        // base underneath still matters: the fill is opaque, but a near-grey catalogue leans on
        // it, and it keeps the corners from showing through during the row's insert animation.
        .background {
            shape
                .fill(.background.secondary)
                .overlay { shape.fill(palette.fill) }
                .overlay {
                    // Inset so the ring sits *inside* the card rather than fattening its edge,
                    // which would make a selected row look a different size from its neighbours.
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

    /// A translucent pane over the gradient rather than a colour of its own, so it reads
    /// consistently wherever on the ramp it sits and doesn't compete with the fill.
    private func iconTile(_ palette: CataloguePalette) -> some View {
        CatalogueIconView(iconName: catalogue.iconName, color: palette.iconGlyph, size: 28)
            .frame(
                width: AppConstants.CatalogueCard.iconTile,
                height: AppConstants.CatalogueCard.iconTile
            )
            .background(
                palette.iconTint,
                in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.medium, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

/// A spread of picks that each used to fail in one appearance or the other: a mid blue, a dark
/// navy and a deep maroon (invisible in dark mode), a pale yellow (invisible in light mode) and
/// a near-neutral grey, which must stay grey rather than being forced into a colour.
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

// Xcode's preview variants cover light and dark from this one definition, so there is no
// second scheme-pinned copy to keep in step.
#Preview("Catalogue cards") {
    let (container, catalogues) = previewCatalogues()
    CatalogueCardGallery(catalogues: catalogues)
        .modelContainer(container)
}
