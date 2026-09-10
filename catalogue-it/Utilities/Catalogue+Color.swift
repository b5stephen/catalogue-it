//
//  Catalogue+Color.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 23/03/2026.
//

import SwiftUI

extension Catalogue {
    /// The catalogue's accent color, exactly as the user picked it.
    ///
    /// Use `palette(for:isSelected:)` for anything that has to *read* against a background —
    /// the raw pick can be near-black, near-white or barely saturated, none of which survive
    /// contact with one of the two appearances.
    var color: Color { Color(hex: colorHex) }

    /// The colours the catalogue cards draw with, normalised for the current appearance.
    func palette(for scheme: ColorScheme, isSelected: Bool = false) -> CataloguePalette {
        CataloguePalette(hex: colorHex, scheme: scheme, isSelected: isSelected)
    }
}

// MARK: - Catalogue Palette

/// A catalogue's colour, resolved into the handful of shades a card actually draws.
///
/// The stored `colorHex` is appearance-independent — the user picks it once and it is the same
/// sRGB value in light and dark. Washing that raw value over the card background at a low
/// opacity is what made dark mode look so subdued: a navy or a maroon over a near-black base is
/// barely distinguishable from an untinted card, and the difference between two such catalogues
/// is smaller still.
///
/// So the pick is treated as a *hue* the user chose rather than a literal fill colour: hue is
/// preserved exactly, while saturation and brightness are pulled into the band that reads well
/// against the appearance in play. Greys stay grey (a colour with almost no saturation is left
/// unsaturated) so a deliberately neutral catalogue isn't forced into a colour.
nonisolated struct CataloguePalette {
    /// The normalised accent — the pick's hue at a saturation and brightness that reads.
    let tint: Color
    /// Solid fill for the icon tile, and the glyph colour that contrasts with it.
    let iconFill: LinearGradient
    let iconGlyph: Color
    /// The wash laid over the card's neutral base.
    let wash: LinearGradient
    /// Card border.
    let border: Color
    let borderWidth: CGFloat
    /// Only drawn in light appearance; a coloured shadow on a dark ground does nothing.
    let shadow: Color
    let shadowRadius: CGFloat

    init(hex: String, scheme: ColorScheme, isSelected: Bool) {
        let isDark = scheme == .dark
        let base = HSB(hex: hex)

        // Near-neutral picks keep their neutrality; everything else is lifted into a band that
        // stays clearly coloured without turning fluorescent.
        let saturation: Double = base.saturation < 0.08
            ? base.saturation
            : min(max(base.saturation, isDark ? 0.58 : 0.48), isDark ? 0.92 : 1.0)
        // Dark mode needs a bright tint to carry over a near-black card; light mode needs the
        // opposite guard, so a pale yellow doesn't wash out against white.
        let brightness = isDark
            ? min(max(base.brightness, 0.76), 1.0)
            : min(max(base.brightness, 0.58), 0.92)

        let accent = Color(hue: base.hue, saturation: saturation, brightness: brightness)
        tint = accent

        // The icon tile is the card's anchor of colour: solid, at full strength, rather than a
        // faint tint behind a coloured glyph. It's a small area, so it can afford to be loud.
        iconFill = LinearGradient(
            colors: [
                Color(hue: base.hue, saturation: saturation * 0.88, brightness: min(brightness * 1.08, 1.0)),
                Color(hue: base.hue, saturation: min(saturation * 1.05, 1.0), brightness: brightness * 0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        // Perceptual luminance of the fill decides whether the glyph goes light or dark, so a
        // yellow tile gets a dark symbol rather than an invisible white one.
        let rgb = RGB(hue: base.hue, saturation: saturation, brightness: brightness)
        let luminance = 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
        iconGlyph = luminance > 0.6
            ? Color(hue: base.hue, saturation: min(saturation + 0.15, 1.0), brightness: 0.18)
            : .white

        // Dark cards can take far more colour than light ones before the name stops being
        // legible, which is the whole reason a single set of opacities looked flat in dark mode.
        let top: Double
        let bottom: Double
        switch (isDark, isSelected) {
        case (true, true):   (top, bottom) = (0.42, 0.20)
        case (true, false):  (top, bottom) = (0.26, 0.11)
        case (false, true):  (top, bottom) = (0.30, 0.14)
        case (false, false): (top, bottom) = (0.21, 0.09)
        }
        // Hues are not equally visible at equal opacity: a blue or a purple over a dark card
        // reads far weaker than a yellow does, and the reverse on a light one. Scaling by the
        // accent's luminance is what stops the navy catalogue looking flat next to the red one.
        let contrast = isDark ? 1 - luminance : luminance
        let weight = 0.78 + contrast * 0.52

        wash = LinearGradient(
            colors: [accent.opacity(top * weight), accent.opacity(bottom * weight)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        border = accent.opacity(isSelected ? 0.9 : min((isDark ? 0.45 : 0.3) * weight, 1))
        borderWidth = isSelected ? 2 : 1
        shadow = isDark ? .clear : accent.opacity(isSelected ? 0.28 : 0.18)
        shadowRadius = isDark ? 0 : 7
    }
}

// MARK: - Colour space helpers

/// Hue/saturation/brightness of a stored hex colour.
///
/// Derived from the hex directly rather than by round-tripping through `UIColor`/`NSColor`, so
/// this stays platform-free and usable outside the main actor.
private nonisolated struct HSB {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)

        let r: Double, g: Double, b: Double
        switch trimmed.count {
        case 3:
            r = Double((value >> 8) * 17) / 255
            g = Double((value >> 4 & 0xF) * 17) / 255
            b = Double((value & 0xF) * 17) / 255
        case 6, 8:
            // An 8-digit value is ARGB; the alpha is dropped, since a card's opacity is the
            // card's business rather than the pick's.
            r = Double(value >> 16 & 0xFF) / 255
            g = Double(value >> 8 & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        default:
            // Same fallback the rest of the app uses for an unparseable hex: system blue.
            r = 0
            g = 122 / 255
            b = 1
        }

        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        brightness = maxValue
        saturation = maxValue == 0 ? 0 : delta / maxValue

        if delta == 0 {
            hue = 0
        } else {
            let h: Double
            switch maxValue {
            case r: h = (g - b) / delta + (g < b ? 6 : 0)
            case g: h = (b - r) / delta + 2
            default: h = (r - g) / delta + 4
            }
            hue = h / 6
        }
    }
}

/// The inverse of `HSB`, used to measure the luminance of a colour we built from components.
private nonisolated struct RGB {
    var red: Double
    var green: Double
    var blue: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        let sector = (hue - hue.rounded(.down)) * 6
        let f = sector - sector.rounded(.down)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))

        switch Int(sector) % 6 {
        case 0: (red, green, blue) = (brightness, t, p)
        case 1: (red, green, blue) = (q, brightness, p)
        case 2: (red, green, blue) = (p, brightness, t)
        case 3: (red, green, blue) = (p, q, brightness)
        case 4: (red, green, blue) = (t, p, brightness)
        default: (red, green, blue) = (brightness, p, q)
        }
    }
}
