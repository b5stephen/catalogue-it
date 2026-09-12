//
//  ItemPaginationControllerReactivityTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Item Pagination Controller Reactivity Tests

/// Covers how `ItemPaginationController` learns about saves: while observing, in standby
/// behind a navigation push, and — the regression guard — when a `reset` arrives while it
/// is still in standby. In compact width, pushing the content column for the second
/// catalogue of a session fires onAppear and onDisappear back to back for a view that
/// stays on screen, so the controller was left deaf and the catalogue's first item never
/// appeared until the user navigated away and back.
///
/// Serialized for the same reason as the sort tests: NSManagedObjectContextDidSave is
/// observed with `object: nil`, so concurrent tests would hear each other's saves.
@Suite(.serialized)
@MainActor
struct ItemPaginationControllerReactivityTests {

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let catalogue: Catalogue
        let definition: FieldDefinition
        let controller: ItemPaginationController
        let fingerprint: FilterFingerprint
    }

    /// An empty catalogue with one text field, and a controller that has loaded (nothing)
    /// for it. On disk, and the catalogue is re-fetched, to match the app: the view holds
    /// an object that came from a query, not from `init`.
    private func makeFixture() throws -> Fixture {
        let url = URL.temporaryDirectory.appending(path: "reactivity-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = container.mainContext

        let inserted = Catalogue(name: "Empty", iconName: "airplane", colorHex: "#000000")
        context.insert(inserted)
        let definition = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        context.insert(definition)
        definition.catalogue = inserted
        try context.save()

        let id = inserted.persistentModelID
        let catalogue = try #require(
            try context.fetch(FetchDescriptor<Catalogue>()).first { $0.persistentModelID == id }
        )

        let controller = ItemPaginationController()
        let fingerprint = FilterFingerprint(
            catalogueID: catalogue.persistentModelID,
            statusTab: .all,
            searchText: "",
            sortFieldKey: ItemSortField.dateAdded.rawValue,
            sortDirection: ItemSortDirection.ascending.rawValue
        )
        controller.reset(fingerprint: fingerprint, context: context)
        #expect(controller.items.isEmpty)

        return Fixture(
            container: container, context: context, catalogue: catalogue,
            definition: definition, controller: controller, fingerprint: fingerprint
        )
    }

    /// Adds one item the way `AddEditItemView.saveItem` does and saves.
    private func addItem(to fixture: Fixture) throws {
        let item = CatalogueItem()
        fixture.context.insert(item)
        item.catalogue = fixture.catalogue
        let value = FieldValue(fieldDefinition: nil, fieldType: .text)
        fixture.context.insert(value)
        value.fieldDefinition = fixture.definition
        value.textValue = "x"
        value.item = item
        try fixture.context.save()
    }

    /// The save notification is delivered through a main-actor Task, so give it a moment.
    private func waitForItems(in controller: ItemPaginationController) async throws {
        for _ in 0..<20 where controller.items.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("A save while observing loads the catalogue's first item")
    func saveWhileObserving() async throws {
        let fixture = try makeFixture()
        fixture.controller.startObservingStoreChanges()

        try addItem(to: fixture)
        try await waitForItems(in: fixture.controller)

        #expect(fixture.controller.items.count == 1)
        #expect(fixture.controller.totalCount == 1)
    }

    @Test("A save in standby is deferred until the view reappears")
    func saveInStandby() async throws {
        let fixture = try makeFixture()
        fixture.controller.startObservingStoreChanges()
        fixture.controller.stopObservingStoreChanges()

        try addItem(to: fixture)
        // Let the standby observer's Task run; the list itself must not change yet.
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.controller.items.isEmpty)

        let didReset = fixture.controller.startObservingStoreChanges()
        #expect(didReset)
        #expect(fixture.controller.items.count == 1)
    }

    @Test("A reset while in standby re-arms observation")
    func resetInStandbyRearms() async throws {
        let fixture = try makeFixture()
        // onAppear, then the spurious onDisappear, then the view's task.
        fixture.controller.startObservingStoreChanges()
        fixture.controller.stopObservingStoreChanges()
        fixture.controller.reset(fingerprint: fixture.fingerprint, context: fixture.context)

        try addItem(to: fixture)
        try await waitForItems(in: fixture.controller)

        #expect(fixture.controller.items.count == 1)
        // Nothing was pending when reset re-armed: reappearing must not force a reload.
        #expect(fixture.controller.startObservingStoreChanges() == false)
    }
}
