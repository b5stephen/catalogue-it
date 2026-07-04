//
//  FieldOptionsTests.swift
//  UnitTests
//
//  Created by Stephen Denekamp on 23/03/2026.
//

import Testing
import Foundation
@testable import catalogue_it

@MainActor
struct FieldOptionsTests {

    @Test func numberOptionsRoundTrip() throws {
        let original = FieldOptions.number(NumberOptions(format: .currency, precision: 2))
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FieldOptions.self, from: encoded)
        #expect(decoded == original)
    }

    @Test func numberOptionsKeyIsPinned() throws {
        let options = FieldOptions.number(NumberOptions())
        let encoded = try JSONEncoder().encode(options)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(json["number"] != nil, "Expected top-level key 'number' in encoded FieldOptions")
        #expect(json.count == 1, "Expected exactly one top-level key")
    }

    @Test func optionListOptionsRoundTrip() throws {
        let original = FieldOptions.optionList(OptionListOptions(options: ["Mint", "Used"], defaultValue: "Mint"))
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FieldOptions.self, from: encoded)
        #expect(decoded == original)
    }

    @Test func optionListOptionsKeyIsPinned() throws {
        let options = FieldOptions.optionList(OptionListOptions())
        let encoded = try JSONEncoder().encode(options)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(json["optionList"] != nil, "Expected top-level key 'optionList' in encoded FieldOptions")
        #expect(json.count == 1, "Expected exactly one top-level key")
    }

    @Test func optionListDefaultsAreEmpty() {
        let options = OptionListOptions()
        #expect(options.options.isEmpty)
        #expect(options.defaultValue == nil)
    }

    @Test func numberOptionsDefaultsArePlainWholeNumbers() {
        let options = NumberOptions()
        #expect(options.format == .number)
        #expect(options.precision == 0)
    }
}
