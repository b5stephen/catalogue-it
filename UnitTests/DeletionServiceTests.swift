//
//  DeletionServiceTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Deletion Service Tests

/// Tests the manual bottom-up delete paths in `DeletionService`.
/// (Automatic SwiftData cascade deletes are covered in CatalogueDeleteTests.)
@MainActor
struct DeletionServiceTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Inserts a catalogue with one field definition and one item that has a value and a photo.
    private func makePopulatedCatalogue(in ctx: ModelContext) -> (Catalogue, CatalogueItem) {
        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)

        // Relationships are assigned after insert: values assigned before insertion can
        // be applied to the store lazily, leaving foreign keys unset until next touched.
        let fieldDef = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        ctx.insert(fieldDef)
        fieldDef.catalogue = catalogue

        let item = CatalogueItem(isWishlist: false)
        ctx.insert(item)
        item.catalogue = catalogue

        let fv = FieldValue(fieldDefinition: nil, fieldType: .text)
        ctx.insert(fv)
        fv.fieldDefinition = fieldDef
        fv.textValue = "Spitfire"
        fv.item = item

        let photo = ItemPhoto(imageData: Data([0xFF, 0xD8, 0xFF]), priority: 0)
        ctx.insert(photo)
        photo.item = item

        return (catalogue, item)
    }

    // MARK: - Item Deletion

    @Test("deleteItem removes the item, its field values, and its photos")
    func deleteItemRemovesChildren() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (_, item) = makePopulatedCatalogue(in: ctx)
        try ctx.save()

        DeletionService.deleteItem(item, in: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ItemPhoto>()).isEmpty)
    }

    @Test("deleteItem leaves the catalogue and field definitions intact")
    func deleteItemKeepsCatalogueAndDefinitions() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (_, item) = makePopulatedCatalogue(in: ctx)
        try ctx.save()

        DeletionService.deleteItem(item, in: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<FieldDefinition>()).count == 1)
    }

    @Test("deleteItemsAndSave deletes a batch and persists in one save")
    func deleteItemsBatch() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, first) = makePopulatedCatalogue(in: ctx)

        let second = CatalogueItem(isWishlist: true)
        second.catalogue = catalogue
        ctx.insert(second)

        let keeper = CatalogueItem(isWishlist: false)
        keeper.catalogue = catalogue
        ctx.insert(keeper)
        try ctx.save()

        DeletionService.deleteItemsAndSave([first, second], in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CatalogueItem>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isWishlist == false)
        #expect(ctx.hasChanges == false, "The batch delete should already be saved")
    }

    // MARK: - Catalogue Deletion

    @Test("deleteCatalogueAndSave removes the entire object graph")
    func deleteCatalogueRemovesGraph() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _) = makePopulatedCatalogue(in: ctx)
        try ctx.save()

        DeletionService.deleteCatalogueAndSave(catalogue, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldDefinition>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ItemPhoto>()).isEmpty)
    }

    @Test("deleteCatalogue removes orphaned field values that have no item")
    func deleteCatalogueRemovesOrphanedFieldValues() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _) = makePopulatedCatalogue(in: ctx)

        // Orphan: reachable only via its field definition — a relationship walk over
        // catalogue.items would never find it.
        // Assign the relationship after insert: assigning it via init before insert can
        // leave the store's foreign key unset until the property is next touched, which
        // would make the orphan unreachable by predicate and this test flaky.
        let orphan = FieldValue(fieldDefinition: nil, fieldType: .text)
        ctx.insert(orphan)
        orphan.fieldDefinition = catalogue.fieldDefinitions.first
        try ctx.save()
        #expect(orphan.fieldDefinition != nil)

        DeletionService.deleteCatalogueAndSave(catalogue, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).isEmpty)
    }

    @Test("deleteCatalogue succeeds before the graph has ever been saved")
    func deleteCatalogueUnsavedGraph() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _) = makePopulatedCatalogue(in: ctx)

        DeletionService.deleteCatalogueAndSave(catalogue, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ItemPhoto>()).isEmpty)
    }

    @Test("deleting the same catalogue twice is harmless")
    func deleteCatalogueTwice() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _) = makePopulatedCatalogue(in: ctx)
        try ctx.save()

        DeletionService.deleteCatalogueAndSave(catalogue, in: ctx)
        DeletionService.deleteCatalogueAndSave(catalogue, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)
    }

    @Test("deleteCatalogue succeeds after a rollback resurrected the graph")
    func deleteCatalogueAfterRollback() throws {
        // Regression test for "Unexpected backing data for snapshot creation:
        // _FullFutureBackingData". Rolling back a pending delete resurrects the models
        // with future backing data; deleting those instances again via the in-memory
        // relationship arrays crashed. Fetch-based deletion must survive this.
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _) = makePopulatedCatalogue(in: ctx)
        try ctx.save()

        DeletionService.deleteCatalogue(catalogue, in: ctx)
        ctx.rollback()
        DeletionService.deleteCatalogueAndSave(catalogue, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldDefinition>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ItemPhoto>()).isEmpty)
    }

    @Test("deleteCatalogue succeeds when the graph was already deleted via another context")
    func deleteCatalogueDeletedElsewhere() throws {
        // Regression test for "backing data could no longer be found in the store":
        // the main context still holds the models, but their rows are already gone.
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, item) = makePopulatedCatalogue(in: ctx)
        try ctx.save()
        _ = catalogue.items // fault relationships into this context
        _ = item.fieldValues

        let other = ModelContext(container)
        let otherItems = try other.fetch(FetchDescriptor<CatalogueItem>())
        for otherItem in otherItems {
            for photo in Array(otherItem.photos) { other.delete(photo) }
            for value in Array(otherItem.fieldValues) { other.delete(value) }
            other.delete(otherItem)
        }
        try other.save()

        DeletionService.deleteCatalogueAndSave(catalogue, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).isEmpty)
    }

    @Test("deleteItem succeeds on an item that was never saved")
    func deleteUnsavedItem() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (_, item) = makePopulatedCatalogue(in: ctx)

        DeletionService.deleteItemsAndSave([item], in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ItemPhoto>()).isEmpty)
    }

    // MARK: - Undo / Restore

    @Test("Deleting a catalogue registers an undoable restore action")
    func deleteCatalogueRegistersUndo() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        ctx.undoManager = undoManager
        let (catalogue, _) = makePopulatedCatalogue(in: ctx)
        try ctx.save()

        undoManager.beginUndoGrouping()
        DeletionService.deleteCatalogueAndSave(catalogue, in: ctx)
        undoManager.endUndoGrouping()

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)
        #expect(undoManager.canUndo)
    }

    @Test("Undo after catalogue deletion restores the full graph, including soft-deleted items")
    func undoRestoresDeletedCatalogue() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        ctx.undoManager = undoManager
        let (catalogue, _) = makePopulatedCatalogue(in: ctx)
        catalogue.name = "Planes"

        let softDeleted = CatalogueItem(isWishlist: false)
        ctx.insert(softDeleted)
        softDeleted.catalogue = catalogue
        softDeleted.deletedDate = Date.now
        try ctx.save()

        undoManager.beginUndoGrouping()
        DeletionService.deleteCatalogueAndSave(catalogue, in: ctx)
        undoManager.endUndoGrouping()
        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)

        undoManager.undo()

        // The restore runs as a Task on the main actor; wait for it to land.
        var restored: Catalogue?
        for _ in 0..<200 where restored == nil {
            try await Task.sleep(for: .milliseconds(10))
            restored = try ctx.fetch(FetchDescriptor<Catalogue>()).first
        }

        let catalogueAfter = try #require(restored)
        #expect(catalogueAfter.name == "Planes")
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).count == 2)
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).count { $0.deletedDate != nil } == 1)
        #expect(try ctx.fetch(FetchDescriptor<FieldDefinition>()).count == 1)
        let values = try ctx.fetch(FetchDescriptor<FieldValue>())
        #expect(values.map(\.textValue) == ["Spitfire"])
        #expect(values.first?.fieldDefinition != nil)
        let photos = try ctx.fetch(FetchDescriptor<ItemPhoto>())
        #expect(photos.map(\.imageData) == [Data([0xFF, 0xD8, 0xFF])])
    }

    @Test("Hard-deleting items does not register a lying native undo action")
    func deleteItemsRegistersNoUndo() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        ctx.undoManager = undoManager
        let (_, item) = makePopulatedCatalogue(in: ctx)
        try ctx.save()

        undoManager.beginUndoGrouping()
        DeletionService.deleteItemsAndSave([item], in: ctx)
        undoManager.endUndoGrouping()
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)

        // canUndo stays true here even for an empty group, so assert behavior instead:
        // undoing must not resurrect the item into the context (a native SwiftData undo
        // registration would re-insert models that later vanish on save).
        undoManager.undo()
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)
        #expect(ctx.insertedModelsArray.isEmpty)
    }

    @Test("deleteCatalogueAndSave leaves sibling catalogues untouched")
    func deleteCatalogueKeepsSiblings() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (doomed, _) = makePopulatedCatalogue(in: ctx)
        let (kept, _) = makePopulatedCatalogue(in: ctx)
        kept.name = "Keep"
        try ctx.save()

        DeletionService.deleteCatalogueAndSave(doomed, in: ctx)

        let catalogues = try ctx.fetch(FetchDescriptor<Catalogue>())
        #expect(catalogues.map(\.name) == ["Keep"])
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).count == 1)
    }
}
