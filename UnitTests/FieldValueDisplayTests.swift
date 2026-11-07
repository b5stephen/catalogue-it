//
//  FieldValueDisplayTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
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

    @Test("Grouping separator is on by default and can be switched off")
    func numberGroupingSeparator() {
        let fv = makeFieldValue(type: .number)
        fv.numberValue = 1234567

        let grouped = fv.displayValue(options: .number(NumberOptions()))
        #expect(grouped.count > 7, "Default options should insert grouping separators")

        let plain = fv.displayValue(options: .number(NumberOptions(usesGroupingSeparator: false)))
        #expect(plain == "1234567")

        let currency = fv.displayValue(options: .number(NumberOptions(format: .currency, precision: 0, usesGroupingSeparator: false)))
        #expect(currency.contains("1234567"), "Grouping off should apply to currency too")
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
        // Noon UTC on 1 Jan 2020 is still in 2020 in every time zone; CI runs west of UTC.
        fv.dateValue = Date(timeIntervalSince1970: 1_577_880_000)
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

    @Test("Booleans display the field's labels, falling back to Yes/No when blank")
    func booleanDisplayUsesLabels() {
        let options = FieldOptions.boolean(BooleanOptions(trueLabel: "Built", falseLabel: "  "))

        let built = makeFieldValue(type: .boolean)
        built.boolValue = true
        #expect(built.displayValue(options: options) == "Built")

        let notBuilt = makeFieldValue(type: .boolean)
        notBuilt.boolValue = false
        #expect(notBuilt.displayValue(options: options) == "No")
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

// MARK: - Item Field Display Tests

/// A Yes/No field is two-state: no value, or no row at all, reads as No.
@MainActor
struct ItemFieldDisplayTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    @Test("A Yes/No field with no row reads as off, with the field's false label")
    func booleanWithoutRow() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Films")
        ctx.insert(catalogue)
        let field = FieldDefinition(name: "Watched", fieldType: .boolean, priority: 0)
        field.fieldOptions = .boolean(BooleanOptions(falseLabel: "Not yet"))
        field.catalogue = catalogue
        ctx.insert(field)
        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)

        #expect(!item.isOn(field))
        #expect(item.displayValue(for: field) == "Not yet")
    }

    @Test("A Yes/No row with a nil value reads as off")
    func booleanWithNilValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let field = FieldDefinition(name: "Watched", fieldType: .boolean, priority: 0)
        ctx.insert(field)
        let item = CatalogueItem()
        ctx.insert(item)
        let value = FieldValue(fieldDefinition: field, fieldType: .boolean)
        value.item = item
        ctx.insert(value)

        #expect(!item.isOn(field))
        #expect(item.displayValue(for: field) == "No")

        value.boolValue = true
        #expect(item.isOn(field))
        #expect(item.displayValue(for: field) == "Yes")
    }

    @Test("Other field types with no row stay empty")
    func textWithoutRow() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let field = FieldDefinition(name: "Title", fieldType: .text, priority: 0)
        ctx.insert(field)
        let item = CatalogueItem()
        ctx.insert(item)

        #expect(item.displayValue(for: field).isEmpty)
    }
}
