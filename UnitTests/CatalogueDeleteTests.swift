//
//  CatalogueDeleteTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Catalogue Delete Tests

/// Tests that deleting a catalogue removes the expected models from the store.
///
/// These directly exercise the cascade rules on the Catalogue model:
///   Catalogue → FieldDefinition (.cascade)
///   Catalogue → CatalogueItem (.cascade) → FieldValue (.cascade)
///                                         → ItemPhoto (.cascade)
@MainActor
struct CatalogueDeleteTests {

    // MARK: - Helper

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - Tests

    @Test("Deleting an empty catalogue removes it from the store")
    func deleteEmptyCatalogue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)

        ctx.delete(catalogue)

        let remaining = try ctx.fetch(FetchDescriptor<Catalogue>())
        #expect(remaining.isEmpty)
    }

    @Test("Deleting a catalogue cascades to field definitions")
    func deleteRemovesFieldDefinitions() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        for i in 0..<3 {
            let fd = FieldDefinition(name: "Field \(i)", fieldType: .text, priority: i)
            fd.catalogue = catalogue
            ctx.insert(fd)
        }

        ctx.delete(catalogue)

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldDefinition>()).isEmpty)
    }

    @Test("Deleting a catalogue cascades to items, field values, and photos")
    func deleteRemovesAllChildren() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)

        let fieldDef = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        fieldDef.catalogue = catalogue
        ctx.insert(fieldDef)

        let item = CatalogueItem(isWishlist: false, notes: "A note")
        item.catalogue = catalogue
        ctx.insert(item)

        let fv = FieldValue(fieldDefinition: fieldDef, fieldType: .text)
        fv.textValue = "Spitfire"
        fv.item = item
        ctx.insert(fv)

        let photo = ItemPhoto(imageData: Data([0xFF, 0xD8, 0xFF]), priority: 0)
        photo.item = item
        ctx.insert(photo)

        ctx.delete(catalogue)

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldDefinition>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ItemPhoto>()).isEmpty)
    }

    @Test("Deleting a catalogue cascades to soft-deleted items")
    func deleteIncludesSoftDeletedItems() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)

        let active = CatalogueItem(isWishlist: false)
        active.catalogue = catalogue
        ctx.insert(active)

        let softDeleted = CatalogueItem(isWishlist: false)
        softDeleted.deletedDate = Date(timeIntervalSince1970: 0)
        softDeleted.catalogue = catalogue
        ctx.insert(softDeleted)

        ctx.delete(catalogue)

        #expect(try ctx.fetch(FetchDescriptor<Catalogue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)
    }

    @Test("Deleting one catalogue does not affect sibling catalogues or their items")
    func deleteLeavesOtherCataloguesIntact() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let keep = Catalogue(name: "Keep", iconName: "star", colorHex: "#000000")
        ctx.insert(keep)
        let keepItem = CatalogueItem(isWishlist: false)
        keepItem.catalogue = keep
        ctx.insert(keepItem)

        let remove = Catalogue(name: "Remove", iconName: "trash", colorHex: "#FF0000")
        ctx.insert(remove)
        let removeItem = CatalogueItem(isWishlist: false)
        removeItem.catalogue = remove
        ctx.insert(removeItem)

        ctx.delete(remove)

        let catalogues = try ctx.fetch(FetchDescriptor<Catalogue>())
        #expect(catalogues.count == 1)
        #expect(catalogues.first?.name == "Keep")

        let items = try ctx.fetch(FetchDescriptor<CatalogueItem>())
        #expect(items.count == 1)
        #expect(items.first?.catalogue?.name == "Keep")
    }
}
