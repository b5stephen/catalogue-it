//
//  CatalogueSortKeyMaintenanceTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Catalogue Sort Key Maintenance Tests

/// Tests the whole-catalogue tiebreak key recompute used after structural field changes.
@MainActor
struct CatalogueSortKeyMaintenanceTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Catalogue with two text fields and one item holding a value for each.
    private func makeCatalogue(in ctx: ModelContext) -> (Catalogue, CatalogueItem, FieldValue, FieldValue) {
        let catalogue = Catalogue(name: "Test")
        ctx.insert(catalogue)

        let airline = FieldDefinition(name: "Airline", fieldType: .text, priority: 0)
        airline.catalogue = catalogue
        ctx.insert(airline)
        let aircraft = FieldDefinition(name: "Aircraft", fieldType: .text, priority: 1)
        aircraft.catalogue = catalogue
        ctx.insert(aircraft)

        let item = CatalogueItem(isWishlist: false)
        item.catalogue = catalogue
        ctx.insert(item)

        let airlineValue = FieldValue(fieldDefinition: airline, fieldType: .text)
        airlineValue.textValue = "Qantas"
        airlineValue.item = item
        ctx.insert(airlineValue)

        let aircraftValue = FieldValue(fieldDefinition: aircraft, fieldType: .text)
        aircraftValue.textValue = "A380"
        aircraftValue.item = item
        ctx.insert(aircraftValue)

        return (catalogue, item, airlineValue, aircraftValue)
    }

    // MARK: - Tests

    @Test("Recompute replaces stale tiebreak keys with the encoder's current output")
    func recomputeUpdatesStaleKeys() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, item, airlineValue, aircraftValue) = makeCatalogue(in: ctx)
        airlineValue.tiebreakKey = "stale"
        aircraftValue.tiebreakKey = "stale"

        await CatalogueSortKeyMaintenance.recomputeTiebreakKeys(for: catalogue, in: ctx)

        let defs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
        let expectedAirline = SortKeyEncoder.tiebreakKey(
            for: airlineValue,
            allFieldValuesOnItem: item.fieldValues,
            fieldDefinitionsByPriority: defs,
            itemCreatedDate: item.createdDate
        )
        #expect(airlineValue.tiebreakKey == expectedAirline)
        #expect(airlineValue.tiebreakKey.contains("a380"), "Airline's tiebreak includes the other field's sort key")
        #expect(aircraftValue.tiebreakKey.contains("qantas"))
    }

    @Test("Soft-deleted items are skipped by the recompute")
    func recomputeSkipsSoftDeletedItems() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, item, airlineValue, _) = makeCatalogue(in: ctx)
        item.deletedDate = .now
        airlineValue.tiebreakKey = "stale"

        await CatalogueSortKeyMaintenance.recomputeTiebreakKeys(for: catalogue, in: ctx)

        #expect(airlineValue.tiebreakKey == "stale", "Deleted items should not be touched")
    }

    @Test("Progress callback reports each processed item up to the total")
    func progressReporting() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _, _) = makeCatalogue(in: ctx)

        let second = CatalogueItem(isWishlist: false)
        second.catalogue = catalogue
        ctx.insert(second)

        var reports: [(Int, Int)] = []
        await CatalogueSortKeyMaintenance.recomputeTiebreakKeys(for: catalogue, in: ctx) { done, total in
            reports.append((done, total))
        }

        #expect(reports.map(\.0) == [1, 2])
        #expect(reports.allSatisfy { $0.1 == 2 })
    }

    @Test("Recompute saves its changes to the store")
    func recomputeSaves() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, airlineValue, _) = makeCatalogue(in: ctx)
        airlineValue.tiebreakKey = "stale"

        await CatalogueSortKeyMaintenance.recomputeTiebreakKeys(for: catalogue, in: ctx)

        #expect(ctx.hasChanges == false, "Recompute should leave no unsaved changes")
    }
}
