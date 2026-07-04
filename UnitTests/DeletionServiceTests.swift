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

        let fieldDef = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        fieldDef.catalogue = catalogue
        ctx.insert(fieldDef)

        let item = CatalogueItem(isWishlist: false)
        item.catalogue = catalogue
        ctx.insert(item)

        let fv = FieldValue(fieldDefinition: fieldDef, fieldType: .text)
        fv.textValue = "Spitfire"
        fv.item = item
        ctx.insert(fv)

        let photo = ItemPhoto(imageData: Data([0xFF, 0xD8, 0xFF]), priority: 0)
        photo.item = item
        ctx.insert(photo)

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
