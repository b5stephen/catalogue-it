//
//  ModelAccessorTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Model Accessor Tests

/// Tests initializer defaults and computed accessors on the SwiftData models.
@MainActor
struct ModelAccessorTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - Catalogue

    @Test("A new catalogue defaults to dateAdded ascending sort and list layout")
    func catalogueDefaults() {
        let catalogue = Catalogue(name: "Test")
        #expect(catalogue.sortFieldKey == ItemSortField.dateAdded.rawValue)
        #expect(catalogue.sortDirection == ItemSortDirection.ascending.rawValue)
        #expect(catalogue.itemLayout == .list)
        #expect(catalogue.gridCardSize == Double(AppConstants.GridCardSize.defaultSize))
        #expect(catalogue.iconName == "square.grid.2x2")
        #expect(catalogue.colorHex == "#007AFF")
        #expect(catalogue.priority == 0)
    }

    @Test("itemLayout round trips through the platform-specific raw storage")
    func itemLayoutRoundTrip() {
        let catalogue = Catalogue(name: "Test")
        catalogue.itemLayout = .grid
        #expect(catalogue.itemLayout == .grid)
        catalogue.itemLayout = .list
        #expect(catalogue.itemLayout == .list)
    }

    @Test("An unrecognized stored layout value falls back to list")
    func itemLayoutFallback() {
        let catalogue = Catalogue(name: "Test")
        catalogue.itemLayoutRaw_mac = "bogus"
        catalogue.itemLayoutRaw_ios = "bogus"
        #expect(catalogue.itemLayout == .list)
    }

    @Test("gridCardSize round trips through the platform-specific storage")
    func gridCardSizeRoundTrip() {
        let catalogue = Catalogue(name: "Test")
        catalogue.gridCardSize = 240
        #expect(catalogue.gridCardSize == 240)
    }

    // MARK: - CatalogueItem

    @Test("isDeleted reflects whether deletedDate is set")
    func isDeletedFlag() {
        let item = CatalogueItem()
        #expect(item.isDeleted == false)
        item.deletedDate = .now
        #expect(item.isDeleted)
    }

    @Test("value(for:) returns the field value matching the definition, or nil")
    func valueForDefinition() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test")
        ctx.insert(catalogue)
        let nameField = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        nameField.catalogue = catalogue
        ctx.insert(nameField)
        let yearField = FieldDefinition(name: "Year", fieldType: .number, priority: 1)
        yearField.catalogue = catalogue
        ctx.insert(yearField)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        let fv = FieldValue(fieldDefinition: nameField, fieldType: .text)
        fv.textValue = "Spitfire"
        fv.item = item
        ctx.insert(fv)

        #expect(item.value(for: nameField)?.textValue == "Spitfire")
        #expect(item.value(for: yearField) == nil, "No value stored for the Year field")
    }

    // MARK: - FieldDefinition

    @Test("numberOptions round trips on a number field")
    func numberOptionsAccessor() {
        let def = FieldDefinition(name: "Price", fieldType: .number)
        #expect(def.numberOptions == nil)

        def.numberOptions = NumberOptions(format: .currency, precision: 2)
        #expect(def.numberOptions == NumberOptions(format: .currency, precision: 2))
        #expect(def.fieldOptions == .number(NumberOptions(format: .currency, precision: 2)))
    }

    @Test("Setting numberOptions on a non-number field is ignored")
    func numberOptionsGuardedByType() {
        let def = FieldDefinition(name: "Name", fieldType: .text)
        def.numberOptions = NumberOptions(format: .currency, precision: 2)
        #expect(def.fieldOptions == nil)
        #expect(def.numberOptions == nil)
    }

    @Test("optionListOptions round trips on an option list field")
    func optionListOptionsAccessor() {
        let def = FieldDefinition(name: "Condition", fieldType: .optionList)
        #expect(def.optionListOptions == nil)

        let options = OptionListOptions(options: ["Mint", "Used"], defaultValue: "Mint")
        def.optionListOptions = options
        #expect(def.optionListOptions == options)
        #expect(def.fieldOptions == .optionList(options))
    }

    @Test("Setting optionListOptions on a non-optionList field is ignored")
    func optionListOptionsGuardedByType() {
        let def = FieldDefinition(name: "Year", fieldType: .number)
        def.optionListOptions = OptionListOptions(options: ["A"])
        #expect(def.fieldOptions == nil)
        #expect(def.optionListOptions == nil)
    }

    @Test("Number accessor returns nil when option list options are stored, and vice versa")
    func crossTypeAccessorsReturnNil() {
        let numberDef = FieldDefinition(name: "Price", fieldType: .number)
        numberDef.numberOptions = NumberOptions()
        #expect(numberDef.optionListOptions == nil)

        let listDef = FieldDefinition(name: "Condition", fieldType: .optionList)
        listDef.optionListOptions = OptionListOptions(options: ["Mint"])
        #expect(listDef.numberOptions == nil)
    }
}
