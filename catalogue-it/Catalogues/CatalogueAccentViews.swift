//
//  CatalogueAccentViews.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Catalogue Wash

/// The ground every screen inside a catalogue sits on.
///
/// The catalogue's colour is carried past the Catalogues screen in two layers. The card's
/// duotone fill becomes a header band on the item list — the moment of stepping into the
/// catalogue — and beneath it the whole screen sits on this faint wash of the tint. The wash
/// is what says you are still inside the catalogue once the band is out of the way, and it is
/// the one thing the item detail screen keeps, so list and detail read as one place.
///
/// Light enough that photos and label text sit on it comfortably; deeper in dark appearance,
/// where the same opacity would vanish against a near-black base.
struct CatalogueWash: View {
    @Environment(\.colorScheme) private var colorScheme
    let catalogue: Catalogue

    var body: some View {
        Self.fill(for: catalogue, in: colorScheme)
            .ignoresSafeArea()
    }

    /// The wash as an opaque fill, for anything pinned over the scrolling content that has to
    /// hide what passes beneath it — the status tab bar — without extending into the safe area.
    static func fill(for catalogue: Catalogue, in scheme: ColorScheme) -> some View {
        catalogue.palette(for: scheme).tint
            .opacity(scheme == .dark ? 0.14 : 0.07)
            .background(.background)
    }
}

// MARK: - Catalogue Band

/// The item list's header: the same duotone fill as the catalogue's card, so opening a
/// catalogue feels like stepping into the card you tapped rather than leaving it behind. It
/// stands in for the navigation title, which is why it carries the name and the count.
///
/// The fill runs up under the navigation bar so the colour reaches the top of the screen and
/// the bar's controls float on it, rather than the band starting as a stripe below them.
struct CatalogueBand: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let catalogue: Catalogue
    let itemCount: Int

    private var countLabel: String {
        itemCount == 1 ? "1 item" : "\(itemCount) items"
    }

    var body: some View {
        let palette = catalogue.palette(
            for: colorScheme,
            increasedContrast: colorSchemeContrast == .increased
        )

        HStack(spacing: 12) {
            CatalogueIconView(iconName: catalogue.iconName, color: palette.iconGlyph, size: 24)
                .frame(width: 44, height: 44)
                .background(
                    palette.iconTint,
                    in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.medium, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(catalogue.name)
                    .font(.title2.bold())
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(countLabel)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { palette.fill.ignoresSafeArea(edges: .top) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Card Fill

/// What a neutral card on the wash is filled with. White in light appearance; in dark, the
/// elevated secondary background rather than pure black, which sat on the tinted wash like
/// a hole rather than a card — the same lift a grouped list gives its cells.
private struct CardFill: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        if environment.colorScheme == .dark {
            AnyShapeStyle(.background.secondary)
        } else {
            AnyShapeStyle(.background)
        }
    }
}

// MARK: - Item Card

/// A neutral card lifted off the wash, for the item list rows.
///
/// Each item is its own card, spaced the way the catalogue cards are, so the card language
/// runs catalogue → item → detail section without a break. The shadow is a plain grey one —
/// the cards are neutral, and a tinted shadow under every row would double up on the wash.
///
/// Because the list row background is clear, the system selection highlight no longer draws,
/// so selection is a tint ring, matching the grid's cards.
struct ItemCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(CardFill(), in: shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(.tint, lineWidth: 2.5)
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 4, y: 1)
            .contentShape(shape)
    }
}

extension View {
    func itemCard(isSelected: Bool = false) -> some View {
        modifier(ItemCardModifier(isSelected: isSelected))
    }
}

// MARK: - Catalogue Section Card

/// A titled group on the item detail screen: a small-caps header in the catalogue's tint
/// over a neutral card. Solid colour is reserved for the header, so the item's own data —
/// the point of the screen — stays black-on-white inside.
struct CatalogueSectionCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tint)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    CardFill(),
                    in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
                )
        }
    }
}
