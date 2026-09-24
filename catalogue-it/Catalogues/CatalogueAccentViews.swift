//
//  CatalogueAccentViews.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Catalogue Wash

/// The ground every screen inside a catalogue sits on.
///
/// The catalogue's colour is carried past the Catalogues screen in two layers. At the top of
/// the screen it is strong: the band on a pushed item list, or the glow wherever list and
/// detail sit side by side. Beneath that the ground keeps the colour in one of two places
/// depending on the appearance.
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
    /// Which safe-area edges the wash runs under. Pushed on a compact stack it fills the
    /// screen; in a split view pass `detailColumnEdges` while the leading column is showing.
    var edges: Edge.Set = .all
    /// Whether the colour pools at the top of the screen, fading into the wash.
    ///
    /// The glow is fixed to the screen rather than the content, so it never moves when the
    /// content scrolls. That is the point of it beside a split view: a band scrolling away in
    /// one column while the other stayed put made the two columns disagree about their top
    /// edge at almost any scroll position. Every column that shows it draws it identically
    /// from the top of the screen, so the tops line up across the divider. Strong enough in
    /// light to carry the catalogue's colour the way the band does, but still light enough at
    /// its strongest that the bar's standard title colour reads over it.
    var glow = false

    /// The distance from the top of the screen over which the glow fades out.
    private static let glowHeight: CGFloat = 340

    /// The edges for the detail column of a split view while the leading column is showing.
    /// The detail column spans the full width with the leading column floating over it as a
    /// safe-area inset, so a wash that ran under the leading edge showed through that
    /// column's glass and tinted the catalogue list. The trailing edge is different: on an
    /// iPhone in landscape its inset is the notch or home-indicator side of the screen, and a
    /// wash that respected it stopped short of the screen edge. Once the leading column is
    /// collapsed the leading inset is that same notch, so the wash goes back to `.all`.
    static let detailColumnEdges: Edge.Set = [.vertical, .trailing]

    var body: some View {
        ZStack(alignment: .top) {
            ground
            if glow {
                LinearGradient(
                    stops: [
                        .init(color: glowColor.opacity(glowStrength), location: 0),
                        .init(color: glowColor.opacity(glowStrength * 0.5), location: 0.5),
                        .init(color: glowColor.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.glowHeight)
            }
        }
        .ignoresSafeArea(edges: edges)
    }

    @ViewBuilder
    private var ground: some View {
        if colorScheme == .dark {
            // Not `.background`: in dark that resolves by interface level, and on iPad
            // the split view's leading column is elevated, so the item list came out
            // grey beside a black detail column.
            Color.black
        } else {
            catalogue.palette(for: .light).tint
                .opacity(0.07)
                .background(.background)
        }
    }

    /// In dark, the same deep, restrained shade of the hue the cards are filled with (see
    /// `CardFill`), a little brighter since it fades out: a vivid colour over black would be
    /// the Catalogues screen's accent strength again, across the top of every column.
    private var glowColor: Color {
        if colorScheme == .dark {
            let base = HSBComponents(hex: catalogue.colorHex)
            let isNeutral = base.saturation < 0.08
            return Color(
                hue: base.hue,
                saturation: isNeutral ? base.saturation : 0.5,
                brightness: isNeutral ? 0.22 : 0.3
            )
        } else {
            return catalogue.palette(for: .light).tint
        }
    }

    private var glowStrength: Double { colorScheme == .dark ? 1 : 0.42 }
}

// MARK: - Catalogue Band

/// How far the item list has scrolled past its top, for the band to collapse by.
///
/// A class rather than state on the catalogue screen, because it changes on every frame of a
/// scroll: only views that read `offset` are invalidated by a write, so the band re-renders
/// and the screen that owns it — toolbar, list and all — does not.
@Observable
final class BandScrollState {
    var offset: CGFloat = 0
}

/// The item list's header where the list is pushed on its own (compact width): the same
/// duotone fill as the catalogue's card, so opening a catalogue feels like stepping into the
/// card you tapped rather than leaving it behind. It stands in for the navigation title on
/// arrival, which is why it carries the name and the count.
///
/// It floats over the list rather than scrolling in it, so it can collapse instead of
/// leaving. As the items scroll, the title row slides up under the bar and fades, and what is
/// left is a strip of the fill holding `accessory` (the status tabs), with the cards passing
/// behind it. Without tabs the strip is nothing but the colour under the bar — the colour
/// stays at the top of every catalogue either way. Cards passed under the tabs when they were
/// scroll content, and no glass made them readable over a photo; a solid fill does.
///
/// The fill runs up under the navigation bar so the colour reaches the top of the screen and
/// the bar's controls float on it. The bar's title appears on it once the title row has
/// mostly gone (`isTitleCollapsed`), so the name is never off screen.
///
/// The list reserves `height` at its top with a spacer, so the first card starts below the
/// band; `scrollState` is what the list reports its scroll through.
struct CatalogueBand<Accessory: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let catalogue: Catalogue
    let itemCount: Int
    let scrollState: BandScrollState
    /// The band's full height, before any collapse.
    @Binding var height: CGFloat
    @Binding var isTitleCollapsed: Bool
    @ViewBuilder let accessory: Accessory

    @State private var titleHeight: CGFloat = 0

    private var countLabel: String {
        itemCount == 1 ? "1 item" : "\(itemCount) items"
    }

    var body: some View {
        let palette = catalogue.palette(
            for: colorScheme,
            increasedContrast: colorSchemeContrast == .increased
        )
        let collapse = min(max(scrollState.offset, 0), titleHeight)
        // Faded out over the first part of the collapse, so the text is gone before it reaches
        // the bar rather than sliding under the bar's own title.
        let titleOpacity = titleHeight > 0 ? 1 - min(collapse / (titleHeight * 0.6), 1) : 1

        VStack(spacing: 0) {
            titleRow(palette)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { titleHeight = $0 }
                .opacity(titleOpacity)
                .accessibilityHidden(titleOpacity == 0)
            accessory
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        // Slid up by the collapse inside a frame shortened by the same amount, so the bottom
        // edge — and the tabs on it — rise with the list until the title row has gone, then
        // stay put.
        .offset(y: -collapse)
        .frame(height: height > 0 ? height - collapse : nil, alignment: .top)
        .clipped()
        .background(alignment: .bottom) {
            // Fixed to the band's full height and pinned to its bottom edge, so the gradient
            // moves rigidly with the collapse instead of re-stretching every frame. Extended
            // far enough up to cover the bar and sideways past the horizontal safe area (the
            // notch and home-indicator sides in landscape) so it reaches the screen edges.
            palette.fill
                .frame(height: height + 600)
                .padding(.horizontal, -600)
                .allowsHitTesting(false)
        }
        .onChange(of: titleHeight > 0 && collapse > titleHeight / 2) { _, collapsed in
            guard collapsed != isTitleCollapsed else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isTitleCollapsed = collapsed }
        }
    }

    private func titleRow(_ palette: CataloguePalette) -> some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The navigation bar's title while the band is under it: the name and count in the band's
/// label colours, so it reads on the fill whichever way the fill went.
struct BandBarTitle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let catalogue: Catalogue
    let countLabel: String

    var body: some View {
        let palette = catalogue.palette(
            for: colorScheme,
            increasedContrast: colorSchemeContrast == .increased
        )
        VStack(spacing: 0) {
            Text(catalogue.name)
                .font(.headline)
                .foregroundStyle(palette.primaryText)
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Card Fill

/// What a card on the ground is filled with.
///
/// White in light appearance, lifted off the wash the way a grouped list lifts its cells. In
/// dark the roles swap: the ground is black and the card carries the catalogue's colour — the
/// hue kept, saturation restrained, brightness deep — so it reads as a coloured card on black,
/// as on the Catalogues screen, but quiet enough that the photo and text on it stay the point.
/// It sits well short of the Catalogues cards' vividness on purpose: those are the accent, and
/// a whole list of them at that strength was more colour than a reading surface wants. A
/// neutral pick stays neutral, and lands on the same lift a grouped cell would get.
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
                saturation: isNeutral ? base.saturation : 0.42,
                brightness: isNeutral ? 0.16 : 0.20
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
            .padding(AppConstants.ItemCard.contentPadding)
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
