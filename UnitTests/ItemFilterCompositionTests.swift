//
//  ItemFilterCompositionTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Filter Composition Tests

/// Drives `ItemPaginationController` end-to-end against a real store to verify that the
/// status tab, flag filters, and search compose with AND.
///
/// This matters because the three filters are applied in different layers — status and
/// search in the `#Predicate`, flags in memory per batch — so their composition is not
/// something the type system can guarantee.
@MainActor
struct ItemFilterCompositionTests {

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let catalogue: Catalogue
        let status: FieldDefinition
        let favourite: FieldDefinition
        let forSale: FieldDefinition
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Films")
        ctx.insert(catalogue)

        let title = FieldDefinition(name: "Title", fieldType: .text, priority: 0)
        title.catalogue = catalogue
        ctx.insert(title)

        let status = FieldDefinition(name: "Status", fieldType: .optionList, priority: 1, displayRole: .statusTabs)
        status.fieldOptions = .optionList(OptionListOptions(options: ["Owned", "Wishlist"], defaultValue: "Owned"))
        status.catalogue = catalogue
        ctx.insert(status)

        let favourite = FieldDefinition(name: "Favourite", fieldType: .boolean, priority: 2, displayRole: .flagFilter)
        favourite.catalogue = catalogue
        ctx.insert(favourite)

        let forSale = FieldDefinition(name: "For Sale", fieldType: .boolean, priority: 3, displayRole: .flagFilter)
        forSale.catalogue = catalogue
        ctx.insert(forSale)

        // Every combination of (status × favourite × forSale), so any filter that leaks or
        // is dropped changes the result set.
        var createdAt = Date(timeIntervalSince1970: 0)
        for statusValue in ["Owned", "Wishlist"] {
            for isFavourite in [true, false] {
                for isForSale in [true, false] {
                    let item = CatalogueItem()
                    createdAt = createdAt.addingTimeInterval(60)
                    item.createdDate = createdAt
                    item.catalogue = catalogue
                    ctx.insert(item)

                    let name = "\(statusValue)-\(isFavourite ? "fav" : "nofav")-\(isForSale ? "sale" : "nosale")"
                    let titleFV = FieldValue(fieldDefinition: title, fieldType: .text)
                    titleFV.textValue = name
                    titleFV.item = item
                    ctx.insert(titleFV)

                    let statusFV = FieldValue(fieldDefinition: status, fieldType: .optionList)
                    statusFV.textValue = statusValue
                    statusFV.item = item
                    ctx.insert(statusFV)

                    let favFV = FieldValue(fieldDefinition: favourite, fieldType: .boolean)
                    favFV.boolValue = isFavourite
                    favFV.item = item
                    ctx.insert(favFV)

                    let saleFV = FieldValue(fieldDefinition: forSale, fieldType: .boolean)
                    saleFV.boolValue = isForSale
                    saleFV.item = item
                    ctx.insert(saleFV)

                    item.searchText = SearchTextBuilder.build(from: item.fieldValues)
                    ItemFacetBuilder.apply(
                        to: item,
                        fieldValues: item.fieldValues,
                        definitions: catalogue.fieldDefinitions
                    )
                }
            }
        }
        try ctx.save()

        return Fixture(container: container, catalogue: catalogue, status: status, favourite: favourite, forSale: forSale)
    }

    /// Loads every page for the given filters and returns the matching item titles.
    private func loadAll(
        _ fixture: Fixture,
        statusTab: StatusTab,
        flags: [UUID] = [],
        searchText: String = ""
    ) -> (titles: [String], totalCount: Int) {
        let controller = ItemPaginationController()
        let fingerprint = FilterFingerprint(
            catalogueID: fixture.catalogue.persistentModelID,
            statusTab: statusTab,
            activeFlagIDs: flags,
            searchText: searchText,
            sortFieldKey: ItemSortField.dateAdded.rawValue,
            sortDirection: ItemSortDirection.ascending.rawValue
        )
        let ctx = fixture.container.mainContext
        controller.reset(fingerprint: fingerprint, context: ctx)
        while controller.hasMore {
            let before = controller.items.count
            controller.loadMore(context: ctx)
            if controller.items.count == before && !controller.hasMore { break }
            if controller.items.count == before { break }
        }
        let titles = controller.items.compactMap { item -> String? in
            item.fieldValues.first { $0.fieldType == .text }?.textValue
        }
        return (titles.sorted(), controller.totalCount)
    }

    // MARK: - Tests

    @Test("The All tab returns every item")
    func allTabReturnsEverything() throws {
        let fixture = try makeFixture()
        let result = loadAll(fixture, statusTab: .all)
        #expect(result.titles.count == 8)
        #expect(result.totalCount == 8)
    }

    @Test("A status tab filters to that status alone")
    func statusTabFilters() throws {
        let fixture = try makeFixture()
        let result = loadAll(fixture, statusTab: .option("Wishlist"))
        #expect(result.titles.count == 4)
        #expect(result.titles.allSatisfy { $0.hasPrefix("Wishlist-") })
        #expect(result.totalCount == 4)
    }

    @Test("A single flag filters without touching status")
    func singleFlagFilters() throws {
        let fixture = try makeFixture()
        let result = loadAll(fixture, statusTab: .all, flags: [fixture.favourite.fieldID])
        #expect(result.titles.count == 4)
        #expect(result.titles.allSatisfy { $0.contains("-fav-") })
        #expect(result.totalCount == 4, "totalCount must account for flags applied outside the predicate")
    }

    @Test("Status and flag compose with AND")
    func statusAndFlagCompose() throws {
        let fixture = try makeFixture()
        let result = loadAll(
            fixture,
            statusTab: .option("Wishlist"),
            flags: [fixture.favourite.fieldID]
        )
        #expect(result.titles == ["Wishlist-fav-nosale", "Wishlist-fav-sale"])
        #expect(result.totalCount == 2)
    }

    @Test("Multiple flags compose with AND, not OR")
    func multipleFlagsCompose() throws {
        let fixture = try makeFixture()
        let result = loadAll(
            fixture,
            statusTab: .all,
            flags: [fixture.favourite.fieldID, fixture.forSale.fieldID]
        )
        #expect(result.titles == ["Owned-fav-sale", "Wishlist-fav-sale"])
        #expect(result.totalCount == 2)
    }

    @Test("Flag order does not change the result")
    func flagOrderIsIrrelevant() throws {
        let fixture = try makeFixture()
        let forward = loadAll(fixture, statusTab: .all, flags: [fixture.favourite.fieldID, fixture.forSale.fieldID])
        let reversed = loadAll(fixture, statusTab: .all, flags: [fixture.forSale.fieldID, fixture.favourite.fieldID])
        #expect(forward.titles == reversed.titles)
    }

    @Test("Status, flags, and search all compose with AND")
    func statusFlagAndSearchCompose() throws {
        let fixture = try makeFixture()
        let result = loadAll(
            fixture,
            statusTab: .option("Owned"),
            flags: [fixture.favourite.fieldID],
            searchText: "nosale"
        )
        #expect(result.titles == ["Owned-fav-nosale"])
    }

    @Test("A filter combination matching nothing yields an empty list, not a stalled one")
    func emptyIntersectionTerminates() throws {
        let fixture = try makeFixture()
        let ctx = fixture.container.mainContext

        // Make the intersection genuinely empty: no Wishlist item is also For Sale.
        let wishlistForSale = try ctx.fetch(FetchDescriptor<CatalogueItem>()).filter {
            $0.statusValue == "Wishlist" && $0.flagKeys.contains(ItemFacetBuilder.flagToken(for: fixture.forSale.fieldID))
        }
        for item in wishlistForSale {
            let fv = try #require(item.value(for: fixture.forSale))
            fv.boolValue = false
            ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: fixture.catalogue.fieldDefinitions)
        }
        try ctx.save()

        let result = loadAll(fixture, statusTab: .option("Wishlist"), flags: [fixture.forSale.fieldID])
        #expect(result.titles.isEmpty)
        #expect(result.totalCount == 0)
    }

    @Test("Filtering still works when the status field is a boolean")
    func booleanBackedStatusFilters() throws {
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Films")
        ctx.insert(catalogue)

        let status = FieldDefinition(name: "Wishlist", fieldType: .boolean, priority: 0, displayRole: .statusTabs)
        status.catalogue = catalogue
        ctx.insert(status)

        for wanted in [true, true, false] {
            let item = CatalogueItem()
            item.catalogue = catalogue
            ctx.insert(item)
            let fv = FieldValue(fieldDefinition: status, fieldType: .boolean)
            fv.boolValue = wanted
            fv.item = item
            ctx.insert(fv)
            ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)
        }
        try ctx.save()

        let controller = ItemPaginationController()
        controller.reset(
            fingerprint: FilterFingerprint(
                catalogueID: catalogue.persistentModelID,
                statusTab: .boolTrue,
                searchText: "",
                sortFieldKey: ItemSortField.dateAdded.rawValue,
                sortDirection: ItemSortDirection.ascending.rawValue
            ),
            context: ctx
        )
        #expect(controller.totalCount == 2)
    }
}
