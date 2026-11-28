//
//  CatalogueExportTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Catalogue Export Tests

/// The Data export file, including a full export → import round trip.
@MainActor
struct CatalogueExportTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    /// Builds a catalogue with two fields (Name: text, Year: number) and one owned item.
    private func makeSampleCatalogue(in ctx: ModelContext) -> (Catalogue, FieldDefinition, FieldDefinition) {
        let catalogue = Catalogue(name: "Planes", iconName: "airplane", colorHex: "#FF0000")
        ctx.insert(catalogue)

        let nameField = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        nameField.catalogue = catalogue
        ctx.insert(nameField)

        let yearField = FieldDefinition(name: "Year", fieldType: .number, priority: 1)
        yearField.catalogue = catalogue
        ctx.insert(yearField)

        let item = CatalogueItem(notes: "First build")
        item.catalogue = catalogue
        ctx.insert(item)

        let name = FieldValue(fieldDefinition: nameField, fieldType: .text)
        name.textValue = "Spitfire"
        name.item = item
        ctx.insert(name)

        let year = FieldValue(fieldDefinition: yearField, fieldType: .number)
        year.numberValue = 1936
        year.item = item
        ctx.insert(year)

        return (catalogue, nameField, yearField)
    }

    // MARK: - Data File

    @Test("A Data file decodes as the current version with full catalogue content")
    func dataFileStructure() async throws {
        let container = try makeContainer()
        let (catalogue, _, _) = makeSampleCatalogue(in: container.mainContext)

        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let written = try await DataFileTestSupport.write(catalogue, in: container, exportedAt: at)
        let file = try written.decoded()

        #expect(file.version == CatalogueExportFile.currentVersion)
        let dto = try #require(file.catalogues.first)
        #expect(dto.name == "Planes")
        #expect(dto.fieldDefinitions.map(\.name) == ["Name", "Year"])
        #expect(dto.items.count == 1)
        #expect(dto.items.first?.fieldValues.count == 2)
        #expect(file.exportedAt == at, "The file and its name carry the same time")
        #expect(
            written.fileName == "Planes \(ExportFileName.stamp(at)).json",
            "The whole catalogue is named for it alone"
        )
    }

    @Test("Leaving photos out omits photo data")
    func dataFileWithoutPhotos() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _) = makeSampleCatalogue(in: ctx)

        let item = try #require(catalogue.items.first)
        let photo = ItemPhoto(imageData: Data([0xFF, 0xD8, 0xFF]), priority: 0, caption: "Box art")
        photo.item = item
        ctx.insert(photo)

        let withPhotos = try await DataFileTestSupport.write(catalogue, in: container, includesPhotos: true).decoded()
        #expect(withPhotos.catalogues.first?.items.first?.photos.count == 1)
        #expect(withPhotos.catalogues.first?.items.first?.photos.first?.caption == "Box art")

        let withoutPhotos = try await DataFileTestSupport.write(catalogue, in: container, includesPhotos: false).decoded()
        #expect(withoutPhotos.catalogues.first?.items.first?.photos.isEmpty == true)
    }

    @Test("Some items: the catalogue's whole setup, only those items, in the order given")
    func dataFileForSomeItems() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, nameField, _) = makeSampleCatalogue(in: ctx)
        var added: [CatalogueItem] = []
        for name in ["Hurricane", "Mosquito", "Lancaster"] {
            let item = CatalogueItem()
            item.catalogue = catalogue
            ctx.insert(item)
            let value = FieldValue(fieldDefinition: nameField, fieldType: .text)
            value.textValue = name
            value.item = item
            ctx.insert(value)
            added.append(item)
        }

        let chosen = [added[2], added[0]]
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let stamp = ExportFileName.stamp(at)
        let written = try await DataFileTestSupport.write(catalogue, in: container, items: chosen, exportedAt: at)
        let dto = try #require(written.decoded().catalogues.first)
        #expect(dto.fieldDefinitions.count == 2)
        #expect(dto.items.map { $0.fieldValues.first?.textValue } == ["Lancaster", "Hurricane"])
        #expect(written.fileName == "Planes – 2 items \(stamp).json")

        let single = try await DataFileTestSupport.write(catalogue, in: container, items: [added[1]], exportedAt: at)
        #expect(single.fileName == "Planes – 1 item \(stamp).json")
    }

    @Test("Soft-deleted items are left out, even when asked for")
    func dataFileExcludesSoftDeleted() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _) = makeSampleCatalogue(in: ctx)

        let deleted = CatalogueItem()
        deleted.deletedDate = Date.now
        deleted.catalogue = catalogue
        ctx.insert(deleted)

        let file = try await DataFileTestSupport.write(catalogue, in: container, items: catalogue.items).decoded()
        #expect(file.catalogues.first?.items.count == 1)
    }

    @Test("Text that spells out the items key doesn't confuse where the items go")
    func dataFileWithAwkwardText() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _) = makeSampleCatalogue(in: ctx)
        catalogue.name = #"Odd "items":[] name"#
        try #require(catalogue.items.first).notes = #"{"items":[]}"#

        let file = try await DataFileTestSupport.write(catalogue, in: container).decoded()
        let dto = try #require(file.catalogues.first)
        #expect(dto.name == #"Odd "items":[] name"#)
        #expect(dto.items.first?.notes == #"{"items":[]}"#)
    }

    @Test("More items than one batch all reach the file")
    func dataFileAcrossBatches() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _) = makeSampleCatalogue(in: ctx)
        for index in 0..<45 {
            let item = CatalogueItem(notes: "Item \(index)")
            item.catalogue = catalogue
            ctx.insert(item)
        }

        let file = try await DataFileTestSupport.write(catalogue, in: container).decoded()
        #expect(file.catalogues.first?.items.count == 46)
    }

    // MARK: - Round Trip

    @Test("Export then import reproduces the catalogue, fields, items, and search text")
    func exportImportRoundTrip() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (original, _, _) = makeSampleCatalogue(in: ctx)
        original.icon = .photo(Data([0xFF, 0xD8, 0xFF, 0x01]))

        let data = try await DataFileTestSupport.write(original, in: container).data
        let imported = try await CatalogueImporter.importCatalogues(
            from: data,
            into: container,
            priorityOffset: 1
        )

        let copy = try #require(imported.first)
        #expect(copy.name == original.name)
        #expect(copy.iconName == original.iconName)
        #expect(copy.icon == original.icon)
        #expect(copy.colorHex == original.colorHex)
        #expect(copy.priority == original.priority + 1, "Priority offset appends after existing catalogues")
        #expect(copy.fieldDefinitions.count == 2)
        let copiedIDs: Set<UUID> = Set(copy.fieldDefinitions.map(\.fieldID))
        let originalIDs: Set<UUID> = Set(original.fieldDefinitions.map(\.fieldID))
        #expect(copiedIDs == originalIDs, "Field IDs are preserved so sort preferences survive the round trip")

        let item = try #require(copy.items.first)
        #expect(item.notes == "First build")
        #expect(item.searchText.contains("spitfire"), "Search text is rebuilt on import")
        let year = try #require(item.fieldValues.first { $0.fieldType == .number })
        #expect(year.numberValue == 1936)
        #expect(item.fieldValues.allSatisfy { $0.sortKey != SortKeyEncoder.missingValueSentinel },
            "Sort keys are recomputed on import")
    }

    // MARK: - Photo Count

    @Test("The preview's photo count covers only the chosen items")
    func photoCountForChosenItems() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _) = makeSampleCatalogue(in: ctx)
        let first = try #require(catalogue.items.first)
        let second = CatalogueItem()
        second.catalogue = catalogue
        ctx.insert(second)
        for (item, count) in [(first, 2), (second, 3)] {
            for index in 0..<count {
                let photo = ItemPhoto(imageData: Data([0xFF]), priority: index)
                photo.item = item
                ctx.insert(photo)
            }
        }
        try ctx.save()

        let writer = DataFileWriter(modelContainer: container)
        #expect(try await writer.photoCount(itemIDs: [first.persistentModelID]) == 2)
        #expect(try await writer.photoCount(itemIDs: [first.persistentModelID, second.persistentModelID]) == 5)
    }
}
