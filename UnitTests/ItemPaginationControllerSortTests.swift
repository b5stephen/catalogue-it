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
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        exhaustedController(fixture: fixture, direction: direction).items
    }

    /// Drives the real pagination path to exhaustion and returns the controller, for
    /// tests that also need `totalCount`.
    private func exhaustedController(
        fixture: Fixture,
        direction: ItemSortDirection,
        statusTab: StatusTab = .all,
        activeFlagIDs: [UUID] = [],
        searchText: String = ""
    ) -> ItemPaginationController {
        let controller = ItemPaginationController()
        let fingerprint = FilterFingerprint(
            catalogueID: fixture.catalogue.persistentModelID,
            statusTab: statusTab,
            activeFlagIDs: activeFlagIDs,
            searchText: searchText,
            sortFieldKey: ItemSortField.field(fixture.airlineDef.fieldID).rawValue,
            sortDirection: direction.rawValue
        )
        controller.reset(fingerprint: fingerprint, context: fixture.context)
        while controller.hasMore {
            controller.loadMore(context: fixture.context)
        }
        return controller
    }

    /// An item with a value for Aircraft only — no `FieldValue` for the Airline sort field.
    @discardableResult
    private func makeAircraftOnlyItem(
        in fixture: Fixture,
        aircraft: String,
        createdDate: Date = Date(timeIntervalSince1970: 10_000)
    ) -> CatalogueItem {
        let item = CatalogueItem()
        item.catalogue = fixture.catalogue
        item.createdDate = createdDate
        fixture.context.insert(item)
        let fv = FieldValue(fieldDefinition: fixture.aircraftDef, fieldType: .text)
        fv.textValue = aircraft
        fv.item = item
        fixture.context.insert(fv)
        fv.sortKey = SortKeyEncoder.sortKey(for: fv)
        fv.tiebreakKey = SortKeyEncoder.tiebreakKey(
            for: fv,
            allFieldValuesOnItem: [fv],
            fieldDefinitionsByPriority: [fixture.airlineDef, fixture.aircraftDef],
            itemCreatedDate: item.createdDate
        )
        return item
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

    /// Regression guard for the catalogue card saying 32 while the list showed 31: an item
    /// with no `FieldValue` for the sort field can't be reached from the FieldValue side, so
    /// it must be counted from the item side and appended after the sorted items.
    @Test("Items with no value for the sort field are counted and appear last", arguments: [ItemSortDirection.ascending, .descending])
    func itemsWithoutSortFieldValueAppearLast(direction: ItemSortDirection) throws {
        let fixture = try makeFixture()

        // A fifth item with an Aircraft value but no Airline value at all.
        let noAirlineItem = makeAircraftOnlyItem(in: fixture, aircraft: "737 MAX")
        try fixture.context.save()

        let controller = exhaustedController(fixture: fixture, direction: direction)
        let actual = controller.items

        // The list's count must agree with the Catalogues-screen card.
        let cardCount = CatalogueSummary.itemCount(for: fixture.catalogue, in: fixture.context)
        #expect(cardCount == 5)
        #expect(controller.totalCount == cardCount)

        // Sorted items first, in the same order as before; the rowless item last either way.
        let sorted = CatalogueItemSort.sorted(
            [fixture.itemA, fixture.itemB, fixture.itemC, fixture.itemD],
            primaryField: .field(fixture.airlineDef.fieldID),
            direction: direction,
            catalogue: fixture.catalogue
        )
        #expect(actual.map(\.persistentModelID) == sorted.map(\.persistentModelID) + [noAirlineItem.persistentModelID])
    }

    @Test("The tail is paged: more rowless items than one page all surface, in createdDate order")
    func rowlessItemsSpanPages() throws {
        let fixture = try makeFixture()
        let rowless = (0..<(ItemPaginationController.pageSize + 10)).map { i in
            makeAircraftOnlyItem(in: fixture, aircraft: "A\(i)", createdDate: Date(timeIntervalSince1970: 10_000 + Double(i)))
        }
        try fixture.context.save()

        let controller = exhaustedController(fixture: fixture, direction: .ascending)

        #expect(controller.totalCount == 4 + rowless.count)
        #expect(controller.items.count == 4 + rowless.count)
        #expect(controller.hasMore == false)
        #expect(Array(controller.items.dropFirst(4)).map(\.persistentModelID) == rowless.map(\.persistentModelID))
    }

    @Test("Without rowless items the stream ends the list")
    func noTailWhenEveryItemHasAValue() throws {
        let fixture = try makeFixture()
        let controller = exhaustedController(fixture: fixture, direction: .ascending)

        #expect(controller.totalCount == 4)
        #expect(controller.items.count == 4)
        #expect(controller.hasMore == false)
    }

    @Test("A rowless item obeys the status tab, search and flag filters like any other")
    func rowlessItemRespectsFilters() throws {
        let fixture = try makeFixture()
        let matching = makeAircraftOnlyItem(in: fixture, aircraft: "737 MAX", createdDate: Date(timeIntervalSince1970: 10_000))
        let other = makeAircraftOnlyItem(in: fixture, aircraft: "A320", createdDate: Date(timeIntervalSince1970: 10_001))
        let flagID = UUID()
        matching.statusValue = "owned"
        matching.searchText = "737 max"
        matching.flagKeys = ItemFacetBuilder.flagToken(for: flagID)
        other.statusValue = "wishlist"
        other.searchText = "a320"
        try fixture.context.save()

        let byTab = exhaustedController(fixture: fixture, direction: .ascending, statusTab: .option("owned"))
        #expect(byTab.items.map(\.persistentModelID) == [matching.persistentModelID])
        #expect(byTab.totalCount == 1)

        let bySearch = exhaustedController(fixture: fixture, direction: .ascending, searchText: "737")
        #expect(bySearch.items.map(\.persistentModelID) == [matching.persistentModelID])
        #expect(bySearch.totalCount == 1)

        let byFlag = exhaustedController(fixture: fixture, direction: .ascending, activeFlagIDs: [flagID])
        #expect(byFlag.items.map(\.persistentModelID) == [matching.persistentModelID])
        #expect(byFlag.totalCount == 1)
    }

    @Test("A duplicate FieldValue for the sort field surfaces its item once")
    func duplicateSortFieldValueSurfacesOnce() throws {
        let fixture = try makeFixture()
        // A merge artefact: a second Airline value on itemA.
        let duplicate = FieldValue(fieldDefinition: fixture.airlineDef, fieldType: .text)
        duplicate.textValue = "Air New Zealand"
        duplicate.item = fixture.itemA
        fixture.context.insert(duplicate)
        duplicate.sortKey = SortKeyEncoder.sortKey(for: duplicate)
        duplicate.tiebreakKey = ""
        try fixture.context.save()

        let controller = exhaustedController(fixture: fixture, direction: .ascending)

        #expect(controller.totalCount == 4)
        #expect(controller.items.count == 4)
        #expect(controller.items.count(where: { $0.persistentModelID == fixture.itemA.persistentModelID }) == 1)
    }
}
