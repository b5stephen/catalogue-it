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
    func palette(
        for scheme: ColorScheme,
        isSelected: Bool = false,
        increasedContrast: Bool = false
    ) -> CataloguePalette {
        CataloguePalette(
            hex: colorHex,
            scheme: scheme,
            isSelected: isSelected,
            increasedContrast: increasedContrast
        )
    }
}

// MARK: - Catalogue Palette

/// A catalogue's colour, resolved into the shades a card actually draws.
///
/// The stored `colorHex` is appearance-independent — the user picks it once and it is the same
/// sRGB value in light and dark. Washing that raw value over a neutral card at a low opacity is
/// what made dark mode look subdued: a navy or a maroon over a near-black base was barely
/// distinguishable from an untinted card, and from the next catalogue along.
///
/// So the accent *is* the card now, as a duotone gradient. The pick is treated as the hue the
/// user chose rather than a literal fill: hue anchors the gradient, saturation and brightness
/// are pulled into the band where a full-bleed fill still looks lit, and the two stops rotate
/// slightly in opposite directions around that hue — a blue runs cyan to indigo, a maroon runs
/// pink to rust. Greys keep their neutrality: a colour with almost no saturation gets no
/// rotation at all, so a deliberately neutral catalogue isn't forced into a colour.
///
/// The constraint changes with the design. A wash had to stay light enough for label text; a
/// solid fill instead has to stay *far enough from* it, so the foreground flips to near-black on
/// bright picks rather than the fill being held back to suit white text.
nonisolated struct CataloguePalette {
    /// The normalised accent, un-rotated — for anything that needs one representative colour:
    /// the screen tint inside a catalogue, tinted labels, the status capsules.
    ///
    /// Lighter than the fill's base in dark appearance — brighter, and eased back from full
    /// saturation. The fill can afford to sit deep and vivid, but the tint is mostly read as
    /// *text* on the dark wash — section headers, tab labels — and a fully saturated red
    /// header on a deep red ground was legible but only just. Pulling it towards a pastel is
    /// what gives it room against a ground of the same hue.
    let tint: Color
    /// The card's fill.
    let fill: LinearGradient
    /// Label colours that clear the fill, whichever direction it went.
    let primaryText: Color
    let secondaryText: Color
    /// The icon tile is translucent rather than a colour of its own, so it reads as a pane over
    /// the gradient and keeps working wherever on the ramp it happens to sit.
    let iconTint: Color
    let iconGlyph: Color
    /// Hairline at rest; the selection ring is inset and drawn in the foreground colour, since
    /// a fully coloured card can no longer signal selection by *becoming* coloured.
    let border: Color
    let borderWidth: CGFloat
    let isSelected: Bool
    /// A coloured drop shadow — the cards now have enough colour to cast one in either
    /// appearance, unlike the old wash.
    let shadow: Color
    let shadowRadius: CGFloat

    init(hex: String, scheme: ColorScheme, isSelected: Bool, increasedContrast: Bool = false) {
        let isDark = scheme == .dark
        let base = HSBComponents(hex: hex)
        self.isSelected = isSelected

        // A bold card needs a strong colour more than it needs the exact pick, so saturation
        // floors high; brightness lands in the band where a full-bleed fill still looks lit
        // rather than muddy, a little deeper in dark appearance.
        let isNeutral = base.saturation < 0.08
        let saturation = isNeutral ? base.saturation : min(max(base.saturation, 0.72), 1.0)
        let brightness = min(max(base.brightness, isDark ? 0.62 : 0.66), isDark ? 0.92 : 0.96)

        tint = Color(
            hue: base.hue,
            saturation: isDark ? min(saturation, 0.7) : saturation,
            brightness: isDark ? max(brightness, 0.85) : brightness
        )

        let rgb = RGBComponents(hue: base.hue, saturation: saturation, brightness: brightness)
        let luminance = 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
        // Which way the foreground goes. A saturated yellow and a navy cannot share one.
        let wantsDarkText = luminance > 0.55

        // How far the two stops rotate. Constant everywhere except the yellow-to-green band,
        // where the eye reads a rotation as a *different colour* rather than as shading — an
        // unscaled shift turned the pale yellow catalogue orange-to-olive.
        let bandOffset = abs(base.hue - 0.22)
        let bandDistance = min(bandOffset, 1 - bandOffset)
        let shiftScale = min(max((bandDistance - 0.08) / 0.12, 0.3), 1)
        // Neutral picks rotate not at all: a grey catalogue stays grey.
        let shift = isNeutral ? 0 : 0.055 * shiftScale

        // The bright stop rotates warm, the deep stop cool — the direction that reads as light
        // falling across the card rather than as two colours fighting.
        let startHue = (base.hue - shift + 1).truncatingRemainder(dividingBy: 1)
        let endHue = (base.hue + shift).truncatingRemainder(dividingBy: 1)
        let start = Color(
            hue: startHue,
            saturation: max(saturation - 0.1, 0),
            brightness: min(brightness + 0.12, 1)
        )
        let end = Color(
            hue: endHue,
            saturation: min(saturation + 0.08, 1),
            brightness: brightness * (increasedContrast ? 0.55 : 0.62)
        )
        fill = LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)

        // At increased contrast the labels go pure, rather than the tinted near-black that
        // otherwise keeps the card feeling like one colour.
        if wantsDarkText {
            primaryText = increasedContrast ? .black : Color(hue: base.hue, saturation: 0.9, brightness: 0.16)
            secondaryText = (increasedContrast ? .black : Color(hue: base.hue, saturation: 0.8, brightness: 0.3))
                .opacity(increasedContrast ? 0.9 : 0.75)
        } else {
            primaryText = .white
            secondaryText = .white.opacity(increasedContrast ? 0.95 : 0.78)
        }

        iconTint = wantsDarkText ? .black.opacity(0.16) : .white.opacity(0.22)
        iconGlyph = wantsDarkText ? Color(hue: base.hue, saturation: 0.95, brightness: 0.18) : .white

        let contrastColor = wantsDarkText ? Color.black : Color.white
        border = isSelected ? contrastColor.opacity(0.95) : contrastColor.opacity(isDark ? 0.16 : 0.22)
        borderWidth = isSelected ? 2.5 : 1

        shadow = Color(hue: base.hue, saturation: saturation, brightness: brightness)
            .opacity(isSelected ? 0.5 : (isDark ? 0.35 : 0.3))
        shadowRadius = isSelected ? 12 : 8
    }
}

// MARK: - Colour space helpers

/// Hue/saturation/brightness of a stored hex colour.
///
/// Derived from the hex directly rather than by round-tripping through `UIColor`/`NSColor`, so
/// this stays platform-free and usable outside the main actor.
nonisolated struct HSBComponents {
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

/// The inverse of `HSBComponents`, used to measure the luminance of a colour we built from components.
nonisolated struct RGBComponents {
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
