//
//  CatalogueColorSuggester.swift
//  catalogue-it
//

import Foundation

/// Picks the starting colour for a new catalogue, preferring one that doesn't look like any
/// catalogue the user already has.
///
/// Colours are compared by hue rather than by hex: existing catalogues may have been picked
/// freely in the colour picker, so a `#0A84FF` should still count as "blue taken". Near-neutral
/// picks (greys, black, white) carry no meaningful hue and claim nothing.
nonisolated enum CatalogueColorSuggester {
    /// Candidates in the order they're offered. System blue stays first so the very first
    /// catalogue looks as it always has; after that, each step jumps well round the wheel.
    static let palette: [String] = [
        "#007AFF", // blue
        "#FF9500", // orange
        "#34C759", // green
        "#AF52DE", // purple
        "#FF3B30", // red
        "#30B0C7", // teal
        "#FF2D55", // pink
        "#FFCC00", // yellow
        "#5856D6", // indigo
    ]

    /// Hue distance (as a fraction of the wheel) under which two colours read as the same.
    /// Kept below the palette's closest pairs (red/pink ~15°, orange/yellow ~13°), so taking
    /// one of them doesn't rule out its neighbour.
    static let sameHueThreshold = 1.0 / 36 // 10°

    /// Below this saturation a colour is treated as neutral and ignored.
    static let neutralSaturation = 0.15

    /// The first palette colour whose hue is clear of every existing one. Once the palette is
    /// exhausted, the candidate furthest from its nearest existing hue — so a long list still
    /// spreads out rather than repeating blue.
    static func suggestedHex(avoiding existingHexes: [String]) -> String {
        let usedHues = existingHexes
            .map { HSBComponents(hex: $0) }
            .filter { $0.saturation >= neutralSaturation }
            .map(\.hue)

        guard !usedHues.isEmpty else { return palette[0] }

        func clearance(_ hex: String) -> Double {
            let hue = HSBComponents(hex: hex).hue
            return usedHues.map { hueDistance(hue, $0) }.min() ?? 1
        }

        if let free = palette.first(where: { clearance($0) >= sameHueThreshold }) {
            return free
        }
        // `max(by:)` keeps the first of equal elements, so ties go to the earlier palette entry.
        return palette.max { clearance($0) < clearance($1) } ?? palette[0]
    }

    /// Shortest distance between two hues around the wheel, in 0…0.5.
    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }
}
