//
//  ColorHexTests.swift
//  UnitTests
//

import Testing
import SwiftUI
@testable import catalogue_it

// MARK: - Color Hex Tests

/// Tests the `Color(hex:)` / `toHex()` conversion pair.
/// Uses only 0x00/0xFF channel values so round trips are exact and immune
/// to floating-point rounding in the platform colour conversion.
@MainActor
struct ColorHexTests {

    @Test("Six-digit hex strings round trip exactly", arguments: [
        "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FFFFFF", "#000000"
    ])
    func sixDigitRoundTrip(hex: String) {
        #expect(Color(hex: hex).toHex() == hex)
    }

    @Test("Hex parsing works without a leading #")
    func hexWithoutHash() {
        #expect(Color(hex: "00FF00").toHex() == "#00FF00")
    }

    @Test("Three-digit hex expands each nibble")
    func threeDigitExpansion() {
        #expect(Color(hex: "#F00").toHex() == "#FF0000")
        #expect(Color(hex: "#0F0").toHex() == "#00FF00")
    }

    @Test("Eight-digit ARGB hex parses RGB channels (alpha dropped by toHex)")
    func eightDigitARGB() {
        #expect(Color(hex: "FFFF0000").toHex() == "#FF0000")
    }

    // MARK: - Colours that don't arrive as four RGBA components

    /// The colour panel's Greyscale sliders (and `.white`/`.black`) hand back a two-component
    /// monochrome colour. Reading channels positionally off `cgColor.components` trapped on
    /// these; resolving to RGB first does not.
    @Test("Greyscale colours convert instead of trapping", arguments: [
        (0.0, "#000000"), (1.0, "#FFFFFF"), (0.5, "#808080")
    ])
    func greyscaleColours(white: Double, expected: String) {
        #expect(Color(white: white).toHex() == expected)
    }

    /// A wide-gamut pick resolves to extended-sRGB components outside 0…1. Those are clamped to
    /// the nearest displayable colour rather than formatted into a nonsense hex.
    @Test("Wide-gamut colours clamp into the sRGB range")
    func wideGamutClamping() {
        let hex = Color(.displayP3, red: 1, green: 0, blue: 0).toHex()
        #expect(hex == "#FF0000")
    }

    @Test("Semantic system colours produce a usable hex")
    func semanticColour() {
        let hex = Color.accentColor.toHex()
        #expect(hex.count == 7)
        #expect(hex.hasPrefix("#"))
    }

    @Test("Invalid hex strings fall back to black")
    func invalidHexFallsBackToBlack() {
        #expect(Color(hex: "not a colour").toHex() == "#000000")
        #expect(Color(hex: "").toHex() == "#000000")
    }
}
