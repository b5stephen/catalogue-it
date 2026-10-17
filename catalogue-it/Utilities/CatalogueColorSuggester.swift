//
//  CatalogueColorSuggester.swift
//  catalogue-it
//

import Foundation

/// Compared by hue, not hex, so a freely picked `#0A84FF` still counts as "blue taken".
/// Near-neutrals claim nothing.
nonisolated enum CatalogueColorSuggester {
    /// System blue first, so the first catalogue looks as it always has; then large jumps.
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

    /// Below the palette's closest pairs (red/pink ~15°, orange/yellow ~13°), so taking one
    /// doesn't rule out its neighbour.
    static let sameHueThreshold = 1.0 / 36 // 10°

    static let neutralSaturation = 0.15

    /// Once the palette is exhausted, the candidate furthest from its nearest existing hue.
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
        // `max(by:)` keeps the first of equals, so ties go to the earlier entry.
        return palette.max { clearance($0) < clearance($1) } ?? palette[0]
    }

    /// In 0…0.5.
    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }
}
