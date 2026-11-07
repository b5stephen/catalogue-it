//
//  ItemSelectionTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Item Selection Tests

@MainActor
struct ItemSelectionTests {

    // MARK: - Fixture

    @MainActor private struct Fixture {
        let container: ModelContainer
        let catalogue: Catalogue
        let title: FieldDefinition
        let favourite: FieldDefinition
        /// Oldest first: a Owned/fav, b Wishlist, c Owned, d Wishlist/fav, e Owned/fav, f Wishlist.
        let items: [CatalogueItem]
        var context: ModelContext { container.mainContext }

        func ids(_ names: String...) -> [PersistentIdentifier] {
            names.map { items["abcdef".distance(from: "abcdef".startIndex, to: "abcdef".firstIndex(of: Character($0))!)].persistentModelID }
        }
    }

    /// `f` has no title, so a sort on Title reaches it only through the tail.
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
        let definitions = [title, status, favourite]

        // Titles run against creation order, so the two sorts disagree.
        let rows: [(String?, String, Bool)] = [
            ("delta", "Owned", true), ("bravo", "Wishlist", false), ("echo", "Owned", false),
            ("alpha", "Wishlist", true), ("charlie", "Owned", true), (nil, "Wishlist", false)
        ]
        var items: [CatalogueItem] = []
        for (index, row) in rows.enumerated() {
            let item = CatalogueItem()
            item.createdDate = Date(timeIntervalSince1970: Double(index + 1) * 60)
            item.catalogue = catalogue
            ctx.insert(item)
            var values: [FieldValue] = []
            func add(_ definition: FieldDefinition, _ configure: (FieldValue) -> Void) {
                let value = FieldValue(fieldDefinition: definition, fieldType: definition.fieldType)
                configure(value)
                value.item = item
                ctx.insert(value)
                values.append(value)
            }
            if let name = row.0 { add(title) { $0.textValue = name } }
            add(status) { $0.textValue = row.1 }
            add(favourite) { $0.boolValue = row.2 }
            for value in values {
                value.sortKey = SortKeyEncoder.sortKey(for: value)
                value.tiebreakKey = SortKeyEncoder.tiebreakKey(
                    for: value,
                    allFieldValuesOnItem: values,
                    fieldDefinitionsByPriority: definitions,
                    itemCreatedDate: item.createdDate
                )
            }
            item.searchText = SearchTextBuilder.build(from: item.fieldValues)
            ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: definitions)
            items.append(item)
        }
        try ctx.save()
        return Fixture(container: container, catalogue: catalogue, title: title, favourite: favourite, items: items)
    }

    private func fingerprint(
        _ fixture: Fixture,
        tab: StatusTab = .all,
        flags: [UUID] = [],
        search: String = "",
        sort: ItemSortField = .dateAdded,
        direction: ItemSortDirection = .ascending
    ) -> FilterFingerprint {
        FilterFingerprint(
            catalogueID: fixture.catalogue.persistentModelID,
            statusTab: tab,
            activeFlagIDs: flags,
            searchText: search,
            sortFieldKey: sort.rawValue,
            sortDirection: direction.rawValue
        )
    }

    // MARK: - Matching

    @Test("Select All resolves to every item in date-added order")
    func matchingAll() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture)
        let ids = try ItemSelection.matching(fp, excluding: []).resolve(in: fixture.context, current: fp)
        #expect(ids == fixture.ids("a", "b", "c", "d", "e", "f"))
    }

    @Test("Descending date-added order reverses the result")
    func matchingDescending() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture, direction: .descending)
        let ids = try ItemSelection.matching(fp, excluding: []).resolve(in: fixture.context, current: fp)
        #expect(ids == fixture.ids("f", "e", "d", "c", "b", "a"))
    }

    @Test("Exclusions are removed and the rest keep their order")
    func matchingExcluding() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture)
        let excluded = Set(fixture.ids("b", "e"))
        let ids = try ItemSelection.matching(fp, excluding: excluded).resolve(in: fixture.context, current: fp)
        #expect(ids == fixture.ids("a", "c", "d", "f"))
    }

    @Test("A status tab, flag and search narrow what Select All covers")
    func matchingFilters() throws {
        let fixture = try makeFixture()
        let owned = fingerprint(fixture, tab: .option("Owned"))
        #expect(try ItemSelection.matching(owned, excluding: []).resolve(in: fixture.context, current: owned)
            == fixture.ids("a", "c", "e"))

        let ownedFavourites = fingerprint(fixture, tab: .option("Owned"), flags: [fixture.favourite.fieldID])
        #expect(try ItemSelection.matching(ownedFavourites, excluding: []).resolve(in: fixture.context, current: ownedFavourites)
            == fixture.ids("a", "e"))

        let searched = fingerprint(fixture, search: "alpha")
        #expect(try ItemSelection.matching(searched, excluding: []).resolve(in: fixture.context, current: searched)
            == fixture.ids("d"))
    }

    @Test("A custom-field sort follows the field, then appends items with no value")
    func matchingCustomSort() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture, sort: .field(fixture.title.fieldID))
        let ids = try ItemSelection.matching(fp, excluding: []).resolve(in: fixture.context, current: fp)
        #expect(ids == fixture.ids("d", "b", "e", "a", "c", "f"))

        let descending = fingerprint(fixture, sort: .field(fixture.title.fieldID), direction: .descending)
        let reversed = try ItemSelection.matching(descending, excluding: []).resolve(in: fixture.context, current: descending)
        #expect(reversed == fixture.ids("c", "a", "e", "b", "d", "f"))
    }

    @Test("A custom-field sort with a filter leaves out the tail item that fails it")
    func matchingCustomSortFiltered() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture, tab: .option("Wishlist"), sort: .field(fixture.title.fieldID))
        let ids = try ItemSelection.matching(fp, excluding: []).resolve(in: fixture.context, current: fp)
        #expect(ids == fixture.ids("d", "b", "f"))

        let owned = fingerprint(fixture, tab: .option("Owned"), sort: .field(fixture.title.fieldID))
        #expect(try ItemSelection.matching(owned, excluding: []).resolve(in: fixture.context, current: owned)
            == fixture.ids("e", "a", "c"))
    }

    // MARK: - Explicit

    @Test("Explicit picks come back in the list's order, not the order chosen")
    func itemsInListOrder() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture)
        let picked = ItemSelection.items(Set(fixture.ids("e", "a", "c")))
        #expect(try picked.resolve(in: fixture.context, current: fp) == fixture.ids("a", "c", "e"))

        let byTitle = fingerprint(fixture, sort: .field(fixture.title.fieldID))
        #expect(try picked.resolve(in: fixture.context, current: byTitle) == fixture.ids("e", "a", "c"))
    }

    @Test("Explicit picks survive a filter that hides them")
    func itemsSpanFilters() throws {
        let fixture = try makeFixture()
        let wishlist = fingerprint(fixture, tab: .option("Wishlist"), search: "zzz")
        let picked = ItemSelection.items(Set(fixture.ids("a", "d", "f")))
        #expect(try picked.resolve(in: fixture.context, current: wishlist) == fixture.ids("a", "d", "f"))
    }

    @Test("Picks that are deleted or empty resolve to what remains")
    func itemsIgnoreDeleted() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture)
        fixture.items[1].deletedDate = .now
        try fixture.context.save()
        let picked = ItemSelection.items(Set(fixture.ids("a", "b")))
        #expect(try picked.resolve(in: fixture.context, current: fp) == fixture.ids("a"))
        #expect(try ItemSelection.none.resolve(in: fixture.context, current: fp).isEmpty)
    }

    @Test("Resolving off the main thread gives the same answer")
    func resolvesInBackground() async throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture, tab: .option("Owned"))
        let ids = try await ItemSelection.matching(fp, excluding: Set(fixture.ids("c")))
            .resolve(in: fixture.container, current: fp)
        #expect(ids == fixture.ids("a", "e"))
    }

    // MARK: - Counting and following

    @Test("Counts need no resolving")
    func counts() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture)
        #expect(ItemSelection.items(Set(fixture.ids("a", "b"))).count(totalMatching: 6) == 2)
        #expect(ItemSelection.matching(fp, excluding: Set(fixture.ids("a"))).count(totalMatching: 6) == 5)
        #expect(ItemSelection.matching(fp, excluding: Set(fixture.ids("a", "b"))).count(totalMatching: 1) == 0)
    }

    @Test("Toggling adds to an explicit pick and excludes from Select All")
    func toggling() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture)
        let a = fixture.items[0].persistentModelID
        let picked = ItemSelection.none.toggled(a)
        #expect(picked.contains(a))
        #expect(!picked.toggled(a).contains(a))

        let all = ItemSelection.matching(fp, excluding: [])
        #expect(all.contains(a))
        #expect(!all.toggled(a).contains(a))
        #expect(all.toggled(a).toggled(a) == all)
    }

    @Test("Select All empties when the filters change and only re-sorts when the sort does")
    func following() throws {
        let fixture = try makeFixture()
        let fp = fingerprint(fixture)
        let all = ItemSelection.matching(fp, excluding: [])

        #expect(all.following(fingerprint(fixture, tab: .option("Owned"))) == .none)
        #expect(all.following(fingerprint(fixture, flags: [fixture.favourite.fieldID])) == .none)
        #expect(all.following(fingerprint(fixture, search: "x")) == .none)

        let resorted = fingerprint(fixture, direction: .descending)
        #expect(all.following(resorted) == .matching(resorted, excluding: []))

        let picked = ItemSelection.items(Set(fixture.ids("a")))
        #expect(picked.following(fingerprint(fixture, tab: .option("Owned"))) == picked)
    }
}
