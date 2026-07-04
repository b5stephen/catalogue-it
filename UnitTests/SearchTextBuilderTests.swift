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

    @Test("Blob joins display values with spaces and lowercases everything")
    func joinsAndLowercases() {
        let name = makeTextValue("Spitfire MkIX")
        let number = FieldValue(fieldDefinition: nil, fieldType: .number)
        number.numberValue = 42
        #expect(SearchTextBuilder.build(from: [name, number]) == "spitfire mkix 42")
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

    @Test("Boolean fields contribute their yes/no display value")
    func booleanContributesYesNo() {
        let flag = FieldValue(fieldDefinition: nil, fieldType: .boolean)
        flag.boolValue = true
        #expect(SearchTextBuilder.build(from: [flag]) == "yes")
    }
}
