//
//  CatalogueIconTests.swift
//  UnitTests
//

import Testing
import Foundation
@testable import catalogue_it

// MARK: - Catalogue Icon Tests

/// Emoji and SF Symbol names share the one `iconName` property, so the rule that tells them
/// apart is what keeps a catalogue's icon rendering correctly. These pin it down.
struct CatalogueIconTests {

    @Test("SF Symbol names are classified as symbols")
    func symbolNames() {
        #expect(CatalogueIcon(storedValue: "airplane") == .symbol("airplane"))
        #expect(CatalogueIcon(storedValue: "square.grid.2x2") == .symbol("square.grid.2x2"))
        #expect(CatalogueIcon(storedValue: "train.side.front.car") == .symbol("train.side.front.car"))
    }

    @Test("Emoji are classified as emoji and survive a round trip")
    func emojiValues() {
        #expect(CatalogueIcon(storedValue: "✈️") == .emoji("✈️"))
        #expect(CatalogueIcon(storedValue: "✈️").storedValue == "✈️")
        #expect(CatalogueIcon(storedValue: "✈️").isEmoji)
        #expect(CatalogueIcon(storedValue: "airplane").isEmoji == false)
    }

    @Test("Multi-scalar emoji stay whole")
    func multiScalarEmoji() {
        // Flags, ZWJ sequences and skin tones are single grapheme clusters, and must not be
        // sliced apart by the one-character cap.
        #expect(CatalogueIcon(storedValue: "🇬🇧") == .emoji("🇬🇧"))
        #expect(CatalogueIcon(storedValue: "👨‍👩‍👧") == .emoji("👨‍👩‍👧"))
    }

    @Test("Only the first emoji of a longer entry is kept")
    func firstEmojiOnly() {
        #expect(CatalogueIcon(storedValue: "🎸🥁🎹") == .emoji("🎸"))
    }

    @Test("An empty or whitespace value falls back to the default symbol")
    func emptyFallsBackToDefault() {
        #expect(CatalogueIcon(storedValue: "") == .symbol(CatalogueIcon.defaultSymbol))
        #expect(CatalogueIcon(storedValue: "   ") == .symbol(CatalogueIcon.defaultSymbol))
    }

    @Test("Plain characters are not mistaken for emoji")
    func plainCharactersAreNotEmoji() {
        // ASCII digits and '#' are emoji-capable scalars, but only count as emoji when they
        // carry the keycap sequence.
        #expect(Character("1").isEmoji == false)
        #expect(Character("#").isEmoji == false)
        #expect(Character("a").isEmoji == false)
        #expect(Character("1️⃣").isEmoji)
        #expect(Character("🎲").isEmoji)
    }
}
