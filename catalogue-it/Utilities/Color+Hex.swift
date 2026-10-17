//
//  Color+Hex.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Color + Hex

extension Color {
    /// Accepts "#FF0000" or "FF0000".
    nonisolated init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Resolved into RGB rather than read off `cgColor.components`, whose count depends on the
    /// colour space: a greyscale pick has two, and indexing blue traps. Wide-gamut components
    /// outside 0…1 are clamped to the nearest sRGB colour, which is all the palette can draw.
    func toHex() -> String {
        let fallback = "#007AFF"
        let r: Double, g: Double, b: Double
#if canImport(UIKit)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        // Fails only for a pattern colour, which a ColorPicker can't produce.
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return fallback
        }
        (r, g, b) = (Double(red), Double(green), Double(blue))
#elseif canImport(AppKit)
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return fallback }
        (r, g, b) = (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
#else
        return fallback
#endif
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", channel(r), channel(g), channel(b))
    }
}
