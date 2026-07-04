//
//  ItemPaginationControllerSortTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Helpers

/// Creates an in-memory SwiftData container for pagination-controller sort testing.
@MainActor
private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Catalogue.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

// MARK: - Item Pagination Controller Sort Tests

/// Cross-validates `ItemPaginationController`'s real, DB-fetch-driven custom-field sort
/// against `CatalogueItemSort.sorted(...)`, the already-trusted in-memory reference
/// implementation. This is the regression guard for the bug where custom-field sort had
/// no tiebreaker at all: before the `tiebreakKey` fix, these tests would fail because the
/// DB fetch order would not match the reference order whenever items tied on the primary
/// field.
///
/// Serialized: each test drives a real ModelContext through ItemPaginationController's
/// NSManagedObjectContextDidSave-based reactivity path, which is unsafe to run concurrently
/// with sibling tests (observed cross-test interference when parallelized).
@Suite(.serialized)
@MainActor
struct ItemPaginationControllerSortTests {

    /// Fixture: an "Airline"/"Aircraft" catalogue mirroring the reported bug's screenshot.
    /// Three items share Airline="Air New Zealand" (two of which also tie on Aircraft,
    /// broken only by createdDate), and one item has a different Airline.
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let catalogue: Catalogue
        let airlineDef: FieldDefinition
        let aircraftDef: FieldDefinition
        let itemA: CatalogueItem // Air New Zealand / 777-319 ER / t0
        let itemB: CatalogueItem // Air New Zealand / 787-9      / t1
        let itemC: CatalogueItem // Air New Zealand / 777-319 ER / t2 (ties itemA on both fields)
        let itemD: CatalogueItem // Ansett New Zealand / BAe 146-300 / t3
    }

    private func makeFixture() throws -> Fixture {
        let container = try makeContainer()
        let context = container.mainContext

        let catalogue = Catalogue(name: "Plane Sorter", iconName: "airplane", colorHex: "#000000")
        context.insert(catalogue)

        let airlineDef = FieldDefinition(name: "Airline", fieldType: .text, priority: 0)
        let aircraftDef = FieldDefinition(name: "Aircraft", fieldType: .text, priority: 1)
        airlineDef.catalogue = catalogue
        aircraftDef.catalogue = catalogue
        context.insert(airlineDef)
        context.insert(aircraftDef)
        let sortedDefs = [airlineDef, aircraftDef]

        func makeItem(airline: String, aircraft: String, createdDate: Date) -> CatalogueItem {
            let item = CatalogueItem()
            item.catalogue = catalogue
            item.createdDate = createdDate
            context.insert(item)

            let airlineFV = FieldValue(fieldDefinition: airlineDef, fieldType: .text)
            airlineFV.textValue = airline
            airlineFV.item = item
            context.insert(airlineFV)

            let aircraftFV = FieldValue(fieldDefinition: aircraftDef, fieldType: .text)
            aircraftFV.textValue = aircraft
            aircraftFV.item = item
            context.insert(aircraftFV)

            let all = [airlineFV, aircraftFV]
            for fv in all {
                fv.sortKey = SortKeyEncoder.sortKey(for: fv)
                fv.tiebreakKey = SortKeyEncoder.tiebreakKey(
                    for: fv,
                    allFieldValuesOnItem: all,
                    fieldDefinitionsByPriority: sortedDefs,
                    itemCreatedDate: item.createdDate
                )
            }
            return item
        }

        let t0 = Date(timeIntervalSince1970: 0)
        let itemA = makeItem(airline: "Air New Zealand", aircraft: "777-319 ER", createdDate: t0)
        let itemB = makeItem(airline: "Air New Zealand", aircraft: "787-9", createdDate: t0.addingTimeInterval(1000))
        let itemC = makeItem(airline: "Air New Zealand", aircraft: "777-319 ER", createdDate: t0.addingTimeInterval(2000))
        let itemD = makeItem(airline: "Ansett New Zealand", aircraft: "BAe 146-300", createdDate: t0.addingTimeInterval(3000))

        try context.save()

        return Fixture(
            container: container, context: context, catalogue: catalogue,
            airlineDef: airlineDef, aircraftDef: aircraftDef,
            itemA: itemA, itemB: itemB, itemC: itemC, itemD: itemD
        )
    }

    /// Drives the real pagination path to exhaustion and returns the resulting items.
    private func fetchAllViaController(
        fixture: Fixture,
        direction: ItemSortDirection
    ) -> [CatalogueItem] {
        let controller = ItemPaginationController()
        let fingerprint = FilterFingerprint(
            catalogueID: fixture.catalogue.persistentModelID,
            tab: .all,
            searchText: "",
            sortFieldKey: ItemSortField.field(fixture.airlineDef.fieldID).rawValue,
            sortDirection: direction.rawValue
        )
        controller.reset(fingerprint: fingerprint, context: fixture.context)
        while controller.hasMore {
            controller.loadMore(context: fixture.context)
        }
        return controller.items
    }

    @Test("Ascending custom-field sort matches the CatalogueItemSort reference order")
    func ascendingMatchesReference() throws {
        let fixture = try makeFixture()
        let allItems = [fixture.itemD, fixture.itemB, fixture.itemC, fixture.itemA] // deliberately unordered

        let expected = CatalogueItemSort.sorted(
            allItems,
            primaryField: .field(fixture.airlineDef.fieldID),
            direction: .ascending,
            catalogue: fixture.catalogue
        )
        let actual = fetchAllViaController(fixture: fixture, direction: .ascending)

        #expect(actual.map(\.persistentModelID) == expected.map(\.persistentModelID))
        // Pin down the exact expected order from the screenshot scenario directly too:
        // Air New Zealand (itemA/itemC tied on Aircraft, broken by createdDate) before
        // itemB (different Aircraft), before the different-Airline itemD.
        #expect(actual.map(\.persistentModelID) == [
            fixture.itemA.persistentModelID,
            fixture.itemC.persistentModelID,
            fixture.itemB.persistentModelID,
            fixture.itemD.persistentModelID
        ])
    }

    @Test("Descending custom-field sort matches the CatalogueItemSort reference order")
    func descendingMatchesReference() throws {
        let fixture = try makeFixture()
        let allItems = [fixture.itemD, fixture.itemB, fixture.itemC, fixture.itemA]

        let expected = CatalogueItemSort.sorted(
            allItems,
            primaryField: .field(fixture.airlineDef.fieldID),
            direction: .descending,
            catalogue: fixture.catalogue
        )
        let actual = fetchAllViaController(fixture: fixture, direction: .descending)

        #expect(actual.map(\.persistentModelID) == expected.map(\.persistentModelID))
        // Primary field reverses (Ansett before Air New Zealand), but tiebreakers stay
        // ascending within the Air New Zealand group, per CatalogueItemSort's documented spec.
        #expect(actual.map(\.persistentModelID) == [
            fixture.itemD.persistentModelID,
            fixture.itemA.persistentModelID,
            fixture.itemC.persistentModelID,
            fixture.itemB.persistentModelID
        ])
    }

    @Test("Items with no value for the sort field are excluded from the custom-field fetch")
    func itemsWithoutSortFieldValueAreExcluded() throws {
        let fixture = try makeFixture()

        // A fifth item with an Aircraft value but no Airline value at all.
        let noAirlineItem = CatalogueItem()
        noAirlineItem.catalogue = fixture.catalogue
        fixture.context.insert(noAirlineItem)
        let aircraftOnlyFV = FieldValue(fieldDefinition: fixture.aircraftDef, fieldType: .text)
        aircraftOnlyFV.textValue = "737 MAX"
        aircraftOnlyFV.item = noAirlineItem
        fixture.context.insert(aircraftOnlyFV)
        aircraftOnlyFV.sortKey = SortKeyEncoder.sortKey(for: aircraftOnlyFV)
        aircraftOnlyFV.tiebreakKey = SortKeyEncoder.tiebreakKey(
            for: aircraftOnlyFV,
            allFieldValuesOnItem: [aircraftOnlyFV],
            fieldDefinitionsByPriority: [fixture.airlineDef, fixture.aircraftDef],
            itemCreatedDate: noAirlineItem.createdDate
        )
        try fixture.context.save()

        let actual = fetchAllViaController(fixture: fixture, direction: .ascending)

        #expect(actual.count == 4, "The item lacking an Airline value should not appear when sorting by Airline")
        #expect(!actual.contains(where: { $0.persistentModelID == noAirlineItem.persistentModelID }))
    }
}
