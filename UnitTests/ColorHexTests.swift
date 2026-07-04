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

    @Test("Invalid hex strings fall back to black")
    func invalidHexFallsBackToBlack() {
        #expect(Color(hex: "not a colour").toHex() == "#000000")
        #expect(Color(hex: "").toHex() == "#000000")
    }
}
