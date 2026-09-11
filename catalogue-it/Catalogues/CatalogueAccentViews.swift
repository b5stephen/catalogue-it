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
/// catalogue — and beneath it the screen keeps the colour in one of two places depending on
/// the appearance.
///
/// In light appearance the ground is this faint wash of the tint over the system background —
/// light enough that photos and label text sit on it comfortably, and no further from the
/// Catalogues screen's grouped grey than a grouped background usually is. It is the one thing
/// the item detail keeps, so list and detail read as one place.
///
/// In dark appearance there is no wash. The Catalogues screen is pure black with the colour
/// on the cards, and a coloured ground here inverted that — the push landed on a screen using
/// the opposite system, and every label had to be re-tuned to clear a ground of its own hue.
/// So the dark ground is the plain system background and the colour moves into the cards
/// instead (see `CardFill`), which is the language the Catalogues screen already speaks.
struct CatalogueWash: View {
    @Environment(\.colorScheme) private var colorScheme
    let catalogue: Catalogue

    var body: some View {
        Group {
            if colorScheme == .dark {
                Rectangle().fill(.background)
            } else {
                catalogue.palette(for: .light).tint
                    .opacity(0.07)
                    .background(.background)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Catalogue Band

/// The item list's header: the same duotone fill as the catalogue's card, so opening a
/// catalogue feels like stepping into the card you tapped rather than leaving it behind. It
/// stands in for the navigation title on arrival, which is why it carries the name and the
/// count; it scrolls away with the items, and the bar's title takes over once it has gone.
///
/// The fill runs up under the navigation bar so the colour reaches the top of the screen and
/// the bar's controls float on it, rather than the band starting as a stripe below them.
///
/// The band is translucent, and deliberately not backed by a material: it scrolls under the
/// bar's soft scroll edge effect like the cards do, and a material would flatten that.
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
        .background {
            // As scroll content the band has no safe area to ignore, so the fill is simply
            // extended upwards — far enough to cover the bar and a rubber-band pull.
            palette.fill.opacity(0.85).padding(.top, -600)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Card Fill

/// What a card on the ground is filled with.
///
/// White in light appearance, lifted off the wash the way a grouped list lifts its cells. In
/// dark the roles swap: the ground is black and the card carries the catalogue's colour — the
/// hue kept, saturation moderate, brightness deep — so it is unmistakably a coloured card on
/// black, as on the Catalogues screen, but quiet enough that the photo and text on it stay the
/// point. A neutral pick stays neutral, and lands on the same lift a grouped cell would get.
private struct CardFill: ShapeStyle {
    /// The hex rather than the catalogue: a `ShapeStyle` is `Sendable`, and a model isn't.
    let colorHex: String

    init(catalogue: Catalogue) { colorHex = catalogue.colorHex }

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        if environment.colorScheme == .dark {
            let base = HSBComponents(hex: colorHex)
            let isNeutral = base.saturation < 0.08
            return AnyShapeStyle(Color(
                hue: base.hue,
                saturation: isNeutral ? base.saturation : 0.55,
                brightness: isNeutral ? 0.20 : 0.26
            ))
        } else {
            return AnyShapeStyle(.background)
        }
    }
}

// MARK: - Item Card

/// A card lifted off the ground, for the item list rows.
///
/// Each item is its own card, spaced the way the catalogue cards are, so the card language
/// runs catalogue → item → detail section without a break. The shadow is a plain grey one in
/// light — the cards are neutral there, and a tinted shadow under every row would double up
/// on the wash — and absent in dark, where the coloured fill does the lifting.
///
/// Because the list row background is clear, the system selection highlight no longer draws,
/// so selection is a tint ring, matching the grid's cards.
struct ItemCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let catalogue: Catalogue
    let isSelected: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(CardFill(catalogue: catalogue), in: shape)
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
    func itemCard(in catalogue: Catalogue, isSelected: Bool = false) -> some View {
        modifier(ItemCardModifier(catalogue: catalogue, isSelected: isSelected))
    }
}

// MARK: - Catalogue Section Card

/// A titled group on the item detail screen: a small-caps header in the catalogue's tint
/// over a card. In light the card is neutral and solid colour is reserved for the header, so
/// the item's own data — the point of the screen — stays black-on-white inside. In dark the
/// card takes the same deep tinted fill as the item rows, so list and detail keep matching.
struct CatalogueSectionCard<Content: View>: View {
    let title: LocalizedStringKey
    let catalogue: Catalogue
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
                    CardFill(catalogue: catalogue),
                    in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
                )
        }
    }
}
