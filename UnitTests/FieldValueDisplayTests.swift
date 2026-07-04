//
//  FieldValueDisplayTests.swift
//  UnitTests
//

import Testing
import Foundation
@testable import catalogue_it

// MARK: - Field Value Display Tests

/// Tests `FieldValue.displayValue(options:)` formatting for every field type.
/// Locale-sensitive output (currency symbols, date wording) is asserted loosely
/// so the tests pass regardless of the simulator locale.
@MainActor
struct FieldValueDisplayTests {

    private func makeFieldValue(type: FieldType) -> FieldValue {
        FieldValue(fieldDefinition: nil, fieldType: type)
    }

    // MARK: - Text

    @Test("Text displays verbatim, nil text displays as empty")
    func textDisplay() {
        let fv = makeFieldValue(type: .text)
        fv.textValue = "Spitfire MkIX"
        #expect(fv.displayValue() == "Spitfire MkIX")

        let missing = makeFieldValue(type: .text)
        #expect(missing.displayValue().isEmpty)
    }

    // MARK: - Number

    @Test("Default number options display with zero fraction digits")
    func numberDefaultPrecision() {
        let fv = makeFieldValue(type: .number)
        fv.numberValue = 42.7
        #expect(fv.displayValue() == "43", "Precision 0 should round to a whole number")
    }

    @Test("Number precision adds fraction digits")
    func numberCustomPrecision() {
        let fv = makeFieldValue(type: .number)
        fv.numberValue = 5
        let options = FieldOptions.number(NumberOptions(format: .number, precision: 2))
        let display = fv.displayValue(options: options)
        #expect(display.hasPrefix("5"))
        #expect(display.hasSuffix("00"), "Precision 2 should pad to two fraction digits")
    }

    @Test("Currency format includes the amount")
    func currencyFormat() {
        let fv = makeFieldValue(type: .number)
        fv.numberValue = 129
        let options = FieldOptions.number(NumberOptions(format: .currency, precision: 0))
        #expect(fv.displayValue(options: options).contains("129"))
    }

    @Test("Nil number displays as empty")
    func missingNumberDisplay() {
        let fv = makeFieldValue(type: .number)
        #expect(fv.displayValue().isEmpty)
    }

    // MARK: - Date

    @Test("Date displays abbreviated with no time, nil date displays as empty")
    func dateDisplay() {
        let fv = makeFieldValue(type: .date)
        fv.dateValue = Date(timeIntervalSince1970: 1_577_836_800) // 1 Jan 2020 UTC
        let display = fv.displayValue()
        #expect(display.contains("2020"))
        #expect(display.contains(":") == false, "Time should be omitted")

        let missing = makeFieldValue(type: .date)
        #expect(missing.displayValue().isEmpty)
    }

    // MARK: - Boolean

    @Test("Booleans display as Yes/No, with nil treated as No")
    func booleanDisplay() {
        let yes = makeFieldValue(type: .boolean)
        yes.boolValue = true
        #expect(yes.displayValue() == "Yes")

        let no = makeFieldValue(type: .boolean)
        no.boolValue = false
        #expect(no.displayValue() == "No")

        let unset = makeFieldValue(type: .boolean)
        #expect(unset.displayValue() == "No")
    }

    // MARK: - Option List

    @Test("Option list displays the stored text verbatim")
    func optionListDisplay() {
        let fv = makeFieldValue(type: .optionList)
        fv.textValue = "Mint"
        #expect(fv.displayValue() == "Mint")

        let missing = makeFieldValue(type: .optionList)
        #expect(missing.displayValue().isEmpty)
    }
}
