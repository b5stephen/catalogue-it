//
//  CatalogueColorSuggesterTests.swift
//  UnitTests
//

import Testing
@testable import catalogue_it

struct CatalogueColorSuggesterTests {

    private let palette = CatalogueColorSuggester.palette

    @Test("The first catalogue starts on system blue")
    func firstCatalogueIsBlue() {
        #expect(CatalogueColorSuggester.suggestedHex(avoiding: []) == "#007AFF")
    }

    @Test("Each new catalogue takes the next unused palette colour")
    func walksThePalette() {
        var existing: [String] = []
        for expected in palette {
            let suggestion = CatalogueColorSuggester.suggestedHex(avoiding: existing)
            #expect(suggestion == expected)
            existing.append(suggestion)
        }
    }

    @Test("A freely picked shade of a palette hue counts as taken")
    func nearbyHueIsTaken() {
        // Dark-mode system blue: different hex, same hue as the palette's blue.
        #expect(CatalogueColorSuggester.suggestedHex(avoiding: ["#0A84FF"]) == "#FF9500")
    }

    @Test("Neutral colours don't claim a hue", arguments: ["#000000", "#FFFFFF", "#8E8E93"])
    func neutralsAreIgnored(hex: String) {
        #expect(CatalogueColorSuggester.suggestedHex(avoiding: [hex]) == "#007AFF")
    }

    @Test("Gaps left by deleted catalogues are filled first")
    func fillsGaps() {
        let existing = palette.filter { $0 != "#34C759" }
        #expect(CatalogueColorSuggester.suggestedHex(avoiding: existing) == "#34C759")
    }

    @Test("With every palette hue taken, the suggestion is still a palette colour")
    func exhaustedPaletteFallsBack() {
        let suggestion = CatalogueColorSuggester.suggestedHex(avoiding: palette + palette)
        #expect(palette.contains(suggestion))
    }

    @Test("Once exhausted, the colour furthest from any existing hue wins")
    func exhaustedPalettePicksWidestGap() {
        // Off-palette picks within 10° of every palette hue. Blue's nearest (#0066FF) is ~5°
        // away, further than any other candidate's.
        let crowding = ["#0066FF", "#FF8800", "#30D158", "#BF5AF2", "#FF453A",
                        "#40C8E0", "#FF375F", "#FFD60A", "#5E5CE6"]
        #expect(CatalogueColorSuggester.suggestedHex(avoiding: crowding) == "#007AFF")
    }

    @Test("Once exhausted, ties go to the earlier palette entry")
    func exhaustedPaletteTieBreak() {
        #expect(CatalogueColorSuggester.suggestedHex(avoiding: palette) == "#007AFF")
    }

    @Test("Hue distance wraps around the wheel")
    func hueDistanceWraps() {
        #expect(abs(CatalogueColorSuggester.hueDistance(0.98, 0.02) - 0.04) < 1e-9)
        #expect(abs(CatalogueColorSuggester.hueDistance(0.25, 0.75) - 0.5) < 1e-9)
    }
}
