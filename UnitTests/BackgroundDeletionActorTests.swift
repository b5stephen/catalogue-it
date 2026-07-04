//
//  BackgroundDeletionActorTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Background Deletion Actor Tests

/// Tests the background teardown of catalogues flagged `pendingDeletion` — the batched
/// item deletion, the launch-time resume sweep, and that unflagged catalogues survive.
/// (The synchronous delete paths the actor reuses are covered in DeletionServiceTests.)
@MainActor
struct BackgroundDeletionActorTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Inserts a catalogue with one field definition and `itemCount` items, each with a
    /// field value and a photo.
    private func makePopulatedCatalogue(
        in ctx: ModelContext,
        name: String = "Test",
        itemCount: Int = 3
    ) -> Catalogue {
        let catalogue = Catalogue(name: name, iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)

        let fieldDef = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        ctx.insert(fieldDef)
        fieldDef.catalogue = catalogue

        for index in 0..<itemCount {
            let item = CatalogueItem(isWishlist: false)
            ctx.insert(item)
            item.catalogue = catalogue

            let fv = FieldValue(fieldDefinition: nil, fieldType: .text)
            ctx.insert(fv)
            fv.fieldDefinition = fieldDef
            fv.textValue = "Item \(index)"
            fv.item = item

            let photo = ItemPhoto(imageData: Data([0xFF, 0xD8, 0xFF]), priority: 0)
            ctx.insert(photo)
            photo.item = item
        }

        return catalogue
    }

    private func count<T: PersistentModel>(_ type: T.Type, in ctx: ModelContext) -> Int {
        (try? ctx.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    /// Runs the teardown from a detached task, as production does: a ModelActor executes
    /// on the *calling* task's thread, so entering it from a MainActor test would run the
    /// whole teardown on the main thread — the exact freeze this actor exists to prevent,
    /// and the assert in `deleteCatalogue` trips on it.
    private func deleteDetached(
        _ container: ModelContainer,
        _ operation: @escaping @Sendable (BackgroundDeletionActor) async -> Void
    ) async {
        let actor = BackgroundDeletionActor(modelContainer: container)
        await Task.detached { await operation(actor) }.value
    }

    // MARK: - Tests

    @Test("deleteCatalogue removes the entire graph from a background context")
    func deleteCatalogueRemovesGraph() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makePopulatedCatalogue(in: ctx)
        catalogue.pendingDeletion = true
        try ctx.save()

        let catalogueID = catalogue.persistentModelID
        await deleteDetached(container) { await $0.deleteCatalogue(id: catalogueID) }

        #expect(count(Catalogue.self, in: ctx) == 0)
        #expect(count(CatalogueItem.self, in: ctx) == 0)
        #expect(count(FieldDefinition.self, in: ctx) == 0)
        #expect(count(FieldValue.self, in: ctx) == 0)
        #expect(count(ItemPhoto.self, in: ctx) == 0)
    }

    @Test("deleteCatalogue leaves other catalogues untouched")
    func deleteCatalogueLeavesSiblings() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let doomed = makePopulatedCatalogue(in: ctx, name: "Doomed")
        let survivor = makePopulatedCatalogue(in: ctx, name: "Survivor", itemCount: 2)
        doomed.pendingDeletion = true
        try ctx.save()

        let doomedID = doomed.persistentModelID
        await deleteDetached(container) { await $0.deleteCatalogue(id: doomedID) }

        #expect(count(Catalogue.self, in: ctx) == 1)
        #expect(count(CatalogueItem.self, in: ctx) == 2)
        #expect(count(FieldDefinition.self, in: ctx) == 1)
        #expect(count(FieldValue.self, in: ctx) == 2)
        #expect(count(ItemPhoto.self, in: ctx) == 2)
        #expect(survivor.name == "Survivor")
    }

    @Test("deleteAllPendingCatalogues sweeps every flagged catalogue and only those")
    func resumeSweepDeletesOnlyFlagged() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let pendingA = makePopulatedCatalogue(in: ctx, name: "Pending A")
        let pendingB = makePopulatedCatalogue(in: ctx, name: "Pending B")
        _ = makePopulatedCatalogue(in: ctx, name: "Keeper")
        pendingA.pendingDeletion = true
        pendingB.pendingDeletion = true
        try ctx.save()

        await deleteDetached(container) { await $0.deleteAllPendingCatalogues() }

        let remaining = try ctx.fetch(FetchDescriptor<Catalogue>())
        #expect(remaining.map(\.name) == ["Keeper"])
        #expect(count(CatalogueItem.self, in: ctx) == 3)
    }

    @Test("deleteCatalogue drains item batches larger than one fetch")
    func deleteCatalogueHandlesMultipleBatches() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // More items than BackgroundDeletionActor.batchSize (200) to force >1 batch.
        let catalogue = Catalogue(name: "Big", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        for _ in 0..<250 {
            let item = CatalogueItem(isWishlist: false)
            ctx.insert(item)
            item.catalogue = catalogue
        }
        catalogue.pendingDeletion = true
        try ctx.save()

        let catalogueID = catalogue.persistentModelID
        await deleteDetached(container) { await $0.deleteCatalogue(id: catalogueID) }

        #expect(count(Catalogue.self, in: ctx) == 0)
        #expect(count(CatalogueItem.self, in: ctx) == 0)
    }
}
