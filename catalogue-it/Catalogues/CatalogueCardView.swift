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
/// Because the row background is clear, the system selection highlight no longer draws, so
/// selection is carried by the card's own tint and border.
struct CatalogueCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
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
        let palette = catalogue.palette(for: colorScheme, isSelected: isSelected)

        HStack(spacing: 14) {
            iconTile(palette)

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
        // the colour is the user's to pick, and a wash keeps the name legible against any of
        // them. The strength of that wash comes from `CataloguePalette`, which normalises the
        // pick per appearance — a single set of opacities left dark mode looking washed out.
        .background {
            shape
                .fill(.background.secondary)
                .overlay { shape.fill(palette.wash) }
                .overlay { shape.strokeBorder(palette.border, lineWidth: palette.borderWidth) }
                .compositingGroup()
                .shadow(color: palette.shadow, radius: palette.shadowRadius, y: 3)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("catalogue-\(catalogue.name)")
    }

    /// The card's anchor of colour: a solid tile at full strength with a contrasting glyph,
    /// rather than a faint tint behind a coloured symbol. It's small enough to be loud, and it
    /// carries the catalogue's identity even where the wash has to stay restrained.
    private func iconTile(_ palette: CataloguePalette) -> some View {
        CatalogueIconView(iconName: catalogue.iconName, color: palette.iconGlyph, size: 28)
            .frame(
                width: AppConstants.CatalogueCard.iconTile,
                height: AppConstants.CatalogueCard.iconTile
            )
            .background(
                palette.iconFill,
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

#Preview("Light") {
    let (container, catalogues) = previewCatalogues()
    CatalogueCardGallery(catalogues: catalogues)
        .modelContainer(container)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    let (container, catalogues) = previewCatalogues()
    CatalogueCardGallery(catalogues: catalogues)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
