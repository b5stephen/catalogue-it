//
//  CatalogueAccentViews.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Catalogue Wash

/// The ground every screen inside a catalogue sits on. In light, a faint wash of the tint, which
/// the item detail keeps too, so list and detail read as one place. In dark, plain black, with
/// the colour in the cards instead (see `CardFill`), as on the Catalogues screen: a coloured
/// dark ground meant re-tuning every label against its hue.
struct CatalogueWash: View {
    @Environment(\.colorScheme) private var colorScheme
    let catalogue: Catalogue
    /// Colour pooled at the top, fixed to the screen rather than the content: a band scrolling
    /// away in one column while the other stayed put left their tops disagreeing. Every column
    /// draws it the same from the top of the screen. Light enough at its strongest for the bar's
    /// standard title colour.
    var glow = false

    private static let glowHeight: CGFloat = 340

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
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var ground: some View {
        if colorScheme == .dark {
            // Not `.background`, which in dark resolves by interface level: the iPad split view's
            // elevated leading column came out grey.
            Color.black
        } else {
            catalogue.palette(for: .light).tint
                .opacity(0.07)
                .background(.background)
        }
    }

    /// In dark, the deep shade the cards use (see `CardFill`), a little brighter since it fades.
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

extension View {
    /// In a split view it is the column's container background, not `.background`: on a
    /// landscape iPhone a column's content stops short of the bottom, out of `ignoresSafeArea`'s
    /// reach, and on iOS 27 the leading column lays a translucent material over what's behind.
    ///
    /// Both are applied either way, so a size-class change doesn't rebuild the screen and lose
    /// its scroll position.
    func catalogueGround(_ catalogue: Catalogue, glow: Bool, inSplitView: Bool) -> some View {
        background {
            if !inSplitView {
                CatalogueWash(catalogue: catalogue, glow: glow)
            }
        }
#if os(iOS)
        .containerBackground(for: .navigation) {
            if inSplitView {
                CatalogueWash(catalogue: catalogue, glow: glow)
            }
        }
#endif
    }
}

// MARK: - Wash Fade Edge

/// Fades content to clear under the bar, in place of the system edge effect, for split-view
/// columns: the system blur took on each column's own content, so the shared glow stopped
/// matching across the divider once either scrolled. The fade covers the whole top safe area,
/// including any `safeAreaBar` outside this modifier.
///
/// Applied either way, so a size-class change doesn't rebuild the scroll view.
private struct WashFadeEdge: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(isEnabled, for: .top)
            .mask {
                // The reader stays in the safe area to report the top inset; only its shape extends under.
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.6),
                                .init(color: .black.opacity(0.4), location: 0.85),
                                .init(color: .black, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: isEnabled ? proxy.safeAreaInsets.top : 0)
                        Color.black
                    }
                    .ignoresSafeArea()
                }
            }
    }
}

extension View {
    func washFadeEdge(_ isEnabled: Bool) -> some View {
        modifier(WashFadeEdge(isEnabled: isEnabled))
    }
}

// MARK: - Catalogue Band

/// A class, not state on the screen, so a per-frame write invalidates only the band.
@Observable
final class BandScrollState {
    var offset: CGFloat = 0
}

/// The pushed item list's header, in the catalogue card's duotone fill, standing in for the
/// navigation title. It floats over the list so it can collapse rather than scroll away,
/// leaving a strip of fill holding `accessory` (the status tabs): cards passing under tabs
/// in scroll content were unreadable over a photo. The fill runs up under the bar; the bar's
/// title appears once the title row has mostly gone (`isTitleCollapsed`).
///
/// The list reserves `height` with a spacer and reports its scroll through `scrollState`.
struct CatalogueBand<Accessory: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let catalogue: Catalogue
    let itemCount: Int
    let scrollState: BandScrollState
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
        // Gone before it reaches the bar, rather than sliding under the bar's own title.
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
        // Slid up inside a frame shortened by the same amount, so the tabs rise with the list until
        // the title row has gone, then stay.
        .offset(y: -collapse)
        .frame(height: height > 0 ? height - collapse : nil, alignment: .top)
        .clipped()
        .background(alignment: .bottom) {
            // Fixed to the full height and pinned to the bottom, so the gradient moves rigidly rather
            // than re-stretching; extended up under the bar and out past the landscape safe areas.
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
            CatalogueIconView(
                icon: catalogue.icon,
                color: palette.iconGlyph,
                size: 24,
                tileCornerRadius: AppConstants.CornerRadius.medium
            )
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

/// In the band's label colours, so it reads on the fill.
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

/// White in light, lifted off the wash like a grouped cell. In dark, a deep, restrained shade
/// of the hue: a coloured card on black like the Catalogues screen, but quieter, since a whole
/// list at that strength is too much for reading. A neutral colour stays neutral.
struct CardFill: ShapeStyle {
    /// A hex rather than the catalogue: a `ShapeStyle` is `Sendable`, a model isn't.
    let colorHex: String

    init(catalogue: Catalogue) { colorHex = catalogue.colorHex }
    init(colorHex: String) { self.colorHex = colorHex }

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

/// The item rows' card. A plain grey shadow in light, where a tinted one would double up on the
/// wash; none in dark, where the fill does the lifting. The clear row background hides the
/// system selection highlight, so selection is a tint ring, as on the grid.
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

/// In light the card is neutral and only the header takes the tint, keeping the item's data
/// black-on-white. In dark it takes the item rows' deep tinted fill.
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
