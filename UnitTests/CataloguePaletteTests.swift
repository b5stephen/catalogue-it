//
//  CataloguePaletteTests.swift
//  UnitTests
//

import Testing
import SwiftUI
@testable import catalogue_it

// MARK: - Catalogue Palette Tests

/// The gradient's deep stop turns away from yellow. Turned towards it, a warm pick's deep stop
/// is olive or brown, and the card looks muddy.
@MainActor
struct CataloguePaletteTests {

    private func deepStop(_ hex: String, scheme: ColorScheme = .light) -> HSBComponents {
        let palette = CataloguePalette(hex: hex, scheme: scheme, isSelected: false)
        let resolved = palette.fillDeepStop.resolve(in: EnvironmentValues())
        let component = { (value: Float) in Int((min(max(value, 0), 1) * 255).rounded()) }
        let hex = String(
            format: "#%02X%02X%02X",
            component(resolved.red), component(resolved.green), component(resolved.blue)
        )
        return HSBComponents(hex: hex)
    }

    /// Signed distance around the wheel from `from` to `to`: positive is up the wheel.
    private func turn(from: Double, to: Double) -> Double {
        var delta = to - from
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        return delta
    }

    @Test("Orange deepens towards red, not olive", arguments: [ColorScheme.light, .dark])
    func orange(scheme: ColorScheme) {
        let pick = HSBComponents(hex: "#FF9500")
        let deep = deepStop("#FF9500", scheme: scheme)
        #expect(turn(from: pick.hue, to: deep.hue) < -0.02)
        #expect(deep.brightness > 0.7, "a dark orange reads as brown")
    }

    @Test("Yellow deepens towards amber, not olive", arguments: [ColorScheme.light, .dark])
    func yellow(scheme: ColorScheme) {
        let pick = HSBComponents(hex: "#FFCC00")
        let deep = deepStop("#FFCC00", scheme: scheme)
        #expect(turn(from: pick.hue, to: deep.hue) < 0)
        #expect(deep.brightness > 0.7, "a dark yellow reads as olive")
    }

    @Test("Red deepens towards crimson, not rust")
    func red() {
        let pick = HSBComponents(hex: "#FF3B30")
        let deep = deepStop("#FF3B30")
        #expect(turn(from: pick.hue, to: deep.hue) < -0.02)
    }

    @Test("Cool picks still deepen up the wheel", arguments: ["#007AFF", "#34C759", "#30B0C7"])
    func coolPicks(hex: String) {
        let pick = HSBComponents(hex: hex)
        let deep = deepStop(hex)
        #expect(turn(from: pick.hue, to: deep.hue) > 0.02)
        #expect(deep.brightness < 0.65)
    }

    @Test("Closeness is full near the centre, none far away, and wraps around red")
    func closeness() {
        #expect(CataloguePalette.closeness(of: 0.06, to: 0.06, full: 0.08, none: 0.16) == 1)
        #expect(CataloguePalette.closeness(of: 0.5, to: 0.06, full: 0.08, none: 0.16) == 0)
        #expect(CataloguePalette.closeness(of: 0.99, to: 0.06, full: 0.08, none: 0.16) == 1)
        #expect(abs(CataloguePalette.closeness(of: 0.18, to: 0.06, full: 0.08, none: 0.16) - 0.5) < 0.0001)
    }
}
