//
//  ItemSortTests.swift
//  UnitTests
//
//  Created by Stephen Denekamp on 25/03/2026.
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Helpers

/// Creates an in-memory SwiftData container for sort testing.
@MainActor
private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Catalogue.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

// MARK: - Item Sort Tests

@MainActor
struct ItemSortTests {

    // MARK: - Text Field Comparison

    struct TextCase {
        let a: String?
        let b: String?
        let expected: Bool?  // nil = equal
    }

    @Test("Text field comparison", arguments: [
        TextCase(a: "Alpha", b: "Beta",  expected: true),   // a < b
        TextCase(a: "Beta",  b: "Alpha", expected: false),  // a > b
        TextCase(a: "Alpha", b: "Alpha", expected: nil),    // equal
        TextCase(a: nil,     b: "Alpha", expected: false),  // a missing → goes last
        TextCase(a: "Alpha", b: nil,     expected: true),   // b missing → b goes last
        TextCase(a: nil,     b: nil,     expected: nil),    // both missing → equal
    ])
    func textFieldComparison(tc: TextCase) throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        let fieldDef = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        fieldDef.catalogue = catalogue
        ctx.insert(fieldDef)

        let itemA = CatalogueItem()
        itemA.catalogue = catalogue
        ctx.insert(itemA)
        if let text = tc.a {
            let fv = FieldValue(fieldDefinition: fieldDef, fieldType: .text)
            fv.textValue = text
            fv.item = itemA
            ctx.insert(fv)
        }

        let itemB = CatalogueItem()
        itemB.catalogue = catalogue
        ctx.insert(itemB)
        if let text = tc.b {
            let fv = FieldValue(fieldDefinition: fieldDef, fieldType: .text)
            fv.textValue = text
            fv.item = itemB
            ctx.insert(fv)
        }

        let result = CatalogueItemSort.compare(
            itemA, itemB,
            byField: .field(fieldDef.fieldID),
            fieldDefinitions: [fieldDef]
        )
        #expect(result == tc.expected)
    }

    // MARK: - Number Field Comparison

    struct NumberCase {
        let a: Double?
        let b: Double?
        let expected: Bool?
    }

    @Test("Number field comparison", arguments: [
        NumberCase(a: 1.0, b: 2.0, expected: true),
        NumberCase(a: 2.0, b: 1.0, expected: false),
        NumberCase(a: 5.0, b: 5.0, expected: nil),
        NumberCase(a: nil, b: 1.0, expected: false),
        NumberCase(a: 1.0, b: nil, expected: true),
        NumberCase(a: nil, b: nil, expected: nil),
    ])
    func numberFieldComparison(tc: NumberCase) throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        let fieldDef = FieldDefinition(name: "Year", fieldType: .number, priority: 0)
        fieldDef.catalogue = catalogue
        ctx.insert(fieldDef)

        let itemA = CatalogueItem()
        itemA.catalogue = catalogue
        ctx.insert(itemA)
        if let num = tc.a {
            let fv = FieldValue(fieldDefinition: fieldDef, fieldType: .number)
            fv.numberValue = num
            fv.item = itemA
            ctx.insert(fv)
        }

        let itemB = CatalogueItem()
        itemB.catalogue = catalogue
        ctx.insert(itemB)
        if let num = tc.b {
            let fv = FieldValue(fieldDefinition: fieldDef, fieldType: .number)
            fv.numberValue = num
            fv.item = itemB
            ctx.insert(fv)
        }

        let result = CatalogueItemSort.compare(
            itemA, itemB,
            byField: .field(fieldDef.fieldID),
            fieldDefinitions: [fieldDef]
        )
        #expect(result == tc.expected)
    }

    // MARK: - Boolean Field Comparison

    @Test("Boolean field comparison", arguments: [
        (false, true,  Bool?.some(true)),   // false < true
        (true,  false, Bool?.some(false)),  // true > false
        (true,  true,  Bool?.none),         // equal
        (false, false, Bool?.none),         // equal
    ] as [(Bool, Bool, Bool?)])
    func boolFieldComparison(a: Bool, b: Bool, expected: Bool?) throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        let fieldDef = FieldDefinition(name: "Owned", fieldType: .boolean, priority: 0)
        fieldDef.catalogue = catalogue
        ctx.insert(fieldDef)

        let itemA = CatalogueItem()
        itemA.catalogue = catalogue
        ctx.insert(itemA)
        let fvA = FieldValue(fieldDefinition: fieldDef, fieldType: .boolean)
        fvA.boolValue = a
        fvA.item = itemA
        ctx.insert(fvA)

        let itemB = CatalogueItem()
        itemB.catalogue = catalogue
        ctx.insert(itemB)
        let fvB = FieldValue(fieldDefinition: fieldDef, fieldType: .boolean)
        fvB.boolValue = b
        fvB.item = itemB
        ctx.insert(fvB)

        let result = CatalogueItemSort.compare(
            itemA, itemB,
            byField: .field(fieldDef.fieldID),
            fieldDefinitions: [fieldDef]
        )
        #expect(result == expected)
    }

    // MARK: - Sort Direction

    @Test("Sort direction", arguments: [ItemSortDirection.ascending, .descending])
    func sortDirection(direction: ItemSortDirection) throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        let fieldDef = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        fieldDef.catalogue = catalogue
        ctx.insert(fieldDef)

        let itemA = CatalogueItem()
        itemA.catalogue = catalogue
        ctx.insert(itemA)
        let fvA = FieldValue(fieldDefinition: fieldDef, fieldType: .text)
        fvA.textValue = "Alpha"
        fvA.item = itemA
        ctx.insert(fvA)

        let itemB = CatalogueItem()
        itemB.catalogue = catalogue
        ctx.insert(itemB)
        let fvB = FieldValue(fieldDefinition: fieldDef, fieldType: .text)
        fvB.textValue = "Zeta"
        fvB.item = itemB
        ctx.insert(fvB)

        let sorted = CatalogueItemSort.sorted(
            [itemB, itemA],
            primaryField: .field(fieldDef.fieldID),
            direction: direction,
            catalogue: catalogue
        )

        if direction == .ascending {
            #expect(sorted.first === itemA, "Ascending: Alpha should come first")
        } else {
            #expect(sorted.first === itemB, "Descending: Zeta should come first")
        }
    }

    // MARK: - Cascading Secondary Sort

    @Test("Cascading sort: ties broken by next field")
    func cascadingSort() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)

        // Field 1 (priority 0): "Brand" — all items share "Acme" (tie)
        let brandDef = FieldDefinition(name: "Brand", fieldType: .text, priority: 0)
        brandDef.catalogue = catalogue
        ctx.insert(brandDef)

        // Field 2 (priority 1): "Model" — tiebreaker
        let modelDef = FieldDefinition(name: "Model", fieldType: .text, priority: 1)
        modelDef.catalogue = catalogue
        ctx.insert(modelDef)

        func makeItem(brand: String, model: String) -> CatalogueItem {
            let item = CatalogueItem()
            item.catalogue = catalogue
            ctx.insert(item)
            let fv1 = FieldValue(fieldDefinition: brandDef, fieldType: .text)
            fv1.textValue = brand
            fv1.item = item
            ctx.insert(fv1)
            let fv2 = FieldValue(fieldDefinition: modelDef, fieldType: .text)
            fv2.textValue = model
            fv2.item = item
            ctx.insert(fv2)
            return item
        }

        let itemC = makeItem(brand: "Acme", model: "Charlie")
        let itemA = makeItem(brand: "Acme", model: "Alpha")
        let itemB = makeItem(brand: "Acme", model: "Bravo")

        let sorted = CatalogueItemSort.sorted(
            [itemC, itemA, itemB],
            primaryField: .field(brandDef.fieldID),
            direction: .ascending,
            catalogue: catalogue
        )

        #expect(sorted[0] === itemA, "First should be Alpha")
        #expect(sorted[1] === itemB, "Second should be Bravo")
        #expect(sorted[2] === itemC, "Third should be Charlie")
    }

    // MARK: - Per-Catalogue Sort Independence

    @Test("Per-catalogue sort keys are independent")
    func perCatalogueSortIndependence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catA = Catalogue(name: "A", iconName: "star", colorHex: "#000000")
        let catB = Catalogue(name: "B", iconName: "star", colorHex: "#000000")
        ctx.insert(catA)
        ctx.insert(catB)

        let fieldA = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        fieldA.catalogue = catA
        ctx.insert(fieldA)

        // Set catalogue A to sort by its custom field
        catA.sortFieldKey = ItemSortField.field(fieldA.fieldID).rawValue
        catA.sortDirection = ItemSortDirection.descending.rawValue

        // Catalogue B remains at defaults
        #expect(catB.sortFieldKey == ItemSortField.dateAdded.rawValue)
        #expect(catB.sortDirection == ItemSortDirection.ascending.rawValue)

        // Catalogue A has its own values
        #expect(catA.sortFieldKey == ItemSortField.field(fieldA.fieldID).rawValue)
        #expect(catA.sortDirection == ItemSortDirection.descending.rawValue)
    }
}
