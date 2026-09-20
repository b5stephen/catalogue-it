//
//  SearchTextBuilderTests.swift
//  UnitTests
//

import Testing
import Foundation
@testable import catalogue_it

// MARK: - Search Text Builder Tests

@MainActor
struct SearchTextBuilderTests {

    private func makeTextValue(_ text: String?) -> FieldValue {
        let fv = FieldValue(fieldDefinition: nil, fieldType: .text)
        fv.textValue = text
        return fv
    }

    @Test("Blob joins values with spaces and lowercases everything")
    func joinsAndLowercases() {
        let name = makeTextValue("Spitfire MkIX")
        let number = FieldValue(fieldDefinition: nil, fieldType: .number)
        number.numberValue = 42
        // No definitions, so no priority: ordered by content.
        #expect(SearchTextBuilder.build(from: [name, number]) == "42 spitfire mkix")
    }

    @Test("Values are ordered by field priority, whatever order the relationship yields")
    func orderedByPriority() {
        let second = FieldDefinition(name: "Aircraft", fieldType: .text, priority: 1)
        let first = FieldDefinition(name: "Airline", fieldType: .text, priority: 0)
        let aircraft = FieldValue(fieldDefinition: second, fieldType: .text)
        aircraft.textValue = "A380"
        let airline = FieldValue(fieldDefinition: first, fieldType: .text)
        airline.textValue = "Qantas"
        #expect(SearchTextBuilder.build(from: [aircraft, airline]) == "qantas a380")
        #expect(SearchTextBuilder.build(from: [airline, aircraft]) == "qantas a380")
    }

    @Test("Empty display values are filtered out, leaving no double spaces")
    func filtersEmptyValues() {
        let a = makeTextValue("Alpha")
        let empty = makeTextValue("")
        let missing = makeTextValue(nil)
        let b = makeTextValue("Beta")
        #expect(SearchTextBuilder.build(from: [a, empty, missing, b]) == "alpha beta")
    }

    @Test("An empty field value array produces an empty blob")
    func emptyInputGivesEmptyBlob() {
        #expect(SearchTextBuilder.build(from: []).isEmpty)
    }

    @Test("Boolean fields are not indexed")
    func booleanIsOmitted() {
        let flag = FieldValue(fieldDefinition: nil, fieldType: .boolean)
        flag.boolValue = true
        #expect(SearchTextBuilder.build(from: [flag, makeTextValue("Alpha")]) == "alpha")
    }

    // MARK: - Canonical form

    /// The blob syncs and is rebuilt on every device after a merge, so two devices must
    /// produce byte-identical blobs from the same values or they rewrite each other forever.

    @Test("Numbers are written without grouping, with a point, and without trailing zeros")
    func numbersAreCanonical() {
        let whole = FieldValue(fieldDefinition: nil, fieldType: .number)
        whole.numberValue = 1_234_567
        let fraction = FieldValue(fieldDefinition: nil, fieldType: .number)
        fraction.numberValue = 12.5
        let negative = FieldValue(fieldDefinition: nil, fieldType: .number)
        negative.numberValue = -3
        #expect(SearchTextBuilder.build(from: [whole, fraction, negative]) == "-3 12.5 1234567")
    }

    @Test("Dates index every GMT day the instant can fall on in some zone, each once")
    func datesCoverEveryZone() {
        let evening = FieldValue(fieldDefinition: nil, fieldType: .date)
        evening.dateValue = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        // Already the 15th east of UTC+2, so both days; −14h is still the 14th.
        #expect(SearchTextBuilder.build(from: [evening]) == "2023-11-14 2023-11-15")

        let midday = FieldValue(fieldDefinition: nil, fieldType: .date)
        midday.dateValue = Date(timeIntervalSince1970: 1_700_000_000 - 10 * 3600) // 12:13:20Z
        #expect(SearchTextBuilder.build(from: [midday]) == "2023-11-13 2023-11-14 2023-11-15")
    }

    // MARK: - Query variants

    @Test("A locale-formatted number query folds onto the canonical form, keeping the raw form")
    func numericQueryIsFolded() {
        let us = Locale(identifier: "en_US")
        #expect(SearchTextBuilder.queryVariants("1,234,567", locale: us) == ("1,234,567", "1234567"))
        #expect(SearchTextBuilder.queryVariants("12.50", locale: us) == ("12.50", "12.5"))
        #expect(SearchTextBuilder.queryVariants("1,979.00", locale: us) == ("1,979.00", "1979"))
        #expect(SearchTextBuilder.queryVariants("12.5", locale: us).canonical == "12.5")

        let de = Locale(identifier: "de_DE")
        #expect(SearchTextBuilder.queryVariants("1.234.567", locale: de).canonical == "1234567")
        #expect(SearchTextBuilder.queryVariants("12,5", locale: de).canonical == "12.5")

        // Typed with a plain space where fr_FR formats U+202F.
        let fr = Locale(identifier: "fr_FR")
        #expect(SearchTextBuilder.queryVariants("1 979", locale: fr).canonical == "1979")
    }

    @Test("Text queries are only lowercased, even when they contain digits")
    func textQueryIsOnlyLowercased() {
        let us = Locale(identifier: "en_US")
        #expect(SearchTextBuilder.queryVariants("Spitfire MkIX", locale: us) == ("spitfire mkix", "spitfire mkix"))
        #expect(SearchTextBuilder.queryVariants("Type 1,5", locale: us) == ("type 1,5", "type 1,5"))
        #expect(SearchTextBuilder.queryVariants("", locale: us) == ("", ""))
    }
}
