//
//  Catalogue+Color.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 23/03/2026.
//

import SwiftUI

extension Catalogue {
    /// Exactly as picked. Use `palette(for:isSelected:)` for anything read against a background:
    /// a pick can be near-black, near-white or barely saturated.
    var color: Color { Color(hex: colorHex) }

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

/// The pick is treated as a hue, not a literal fill: the card is a duotone gradient with
/// saturation and brightness pulled into a band where a full-bleed fill looks lit, and the two
/// stops rotated slightly either way around the hue (a blue runs cyan to indigo). Near-greys
/// don't rotate. The foreground flips to near-black on bright picks rather than holding the
/// fill back for white text.
nonisolated struct CataloguePalette {
    /// One representative colour for tint and tinted labels. Brighter and less saturated than
    /// the fill in dark: it's mostly read as small text, and saturated blues and reds carry little
    /// luminance on black.
    let tint: Color
    let fill: LinearGradient
    /// For the catalogue's colour as text on a light pill over the fill.
    let fillDeepStop: Color
    /// What the system draws over the fill (a bar title) needs the matching scheme.
    let prefersDarkForeground: Bool
    let primaryText: Color
    let secondaryText: Color
    /// Translucent, so it reads anywhere on the ramp.
    let iconTint: Color
    let iconGlyph: Color
    /// Hairline at rest; selection is an inset ring, since a coloured card can't signal it by
    /// becoming coloured.
    let border: Color
    let borderWidth: CGFloat
    let isSelected: Bool
    let shadow: Color
    let shadowRadius: CGFloat

    init(hex: String, scheme: ColorScheme, isSelected: Bool, increasedContrast: Bool = false) {
        let isDark = scheme == .dark
        let base = HSBComponents(hex: hex)
        self.isSelected = isSelected

        // Saturation floors high; brightness lands where a full-bleed fill looks lit, not muddy.
        let isNeutral = base.saturation < 0.08
        let saturation = isNeutral ? base.saturation : min(max(base.saturation, 0.72), 1.0)
        let brightness = min(max(base.brightness, isDark ? 0.62 : 0.66), isDark ? 0.92 : 0.96)

        tint = Color(
            hue: base.hue,
            saturation: isDark ? min(saturation, 0.6) : saturation,
            brightness: isDark ? max(brightness, 0.95) : brightness
        )

        let rgb = RGBComponents(hue: base.hue, saturation: saturation, brightness: brightness)
        let luminance = 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
        // A saturated yellow and a navy can't share a foreground.
        let wantsDarkText = luminance > 0.55

        // Scaled down in the yellow-to-green band, where the eye reads rotation as a different
        // colour: unscaled, pale yellow ran orange to olive.
        let bandOffset = abs(base.hue - 0.22)
        let bandDistance = min(bandOffset, 1 - bandOffset)
        let shiftScale = min(max((bandDistance - 0.08) / 0.12, 0.3), 1)
        let shift = isNeutral ? 0 : 0.055 * shiftScale

        // Bright stop warm, deep stop cool: reads as light falling across the card.
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
        fillDeepStop = end
        prefersDarkForeground = wantsDarkText

        // Pure at increased contrast, rather than the tinted near-black.
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

/// From the hex directly rather than through `UIColor`/`NSColor`, so it's platform-free and
/// usable off the main actor.
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
            // ARGB: the alpha is dropped.
            r = Double(value >> 16 & 0xFF) / 255
            g = Double(value >> 8 & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        default:
            // The app's fallback for an unparseable hex.
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

/// For measuring the luminance of a colour built from components.
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
