//
//  CatalogueExportTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Catalogue Export Tests

/// Tests CSV generation and JSON export (including a full export → import round trip).
@MainActor
struct CatalogueExportTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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

        let item = CatalogueItem(isWishlist: false, notes: "First build")
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

    // MARK: - CSV

    @Test("CSV header lists Tab, fields by priority, Notes, and Photo Count")
    func csvHeaderOrder() throws {
        let container = try makeContainer()
        let (catalogue, _, _) = makeSampleCatalogue(in: container.mainContext)

        let csv = CatalogueExporter.csvString(for: catalogue)
        let header = try #require(csv.components(separatedBy: "\n").first)
        #expect(header == "Tab,Name,Year,Notes,Photo Count")
    }

    @Test("CSV data row contains tab, field values, notes, and photo count")
    func csvDataRow() throws {
        let container = try makeContainer()
        let (catalogue, _, _) = makeSampleCatalogue(in: container.mainContext)

        let rows = CatalogueExporter.csvString(for: catalogue).components(separatedBy: "\n")
        try #require(rows.count == 2)
        #expect(rows[1] == "Owned,Spitfire,1936,First build,0")
    }

    @Test("CSV escapes cells containing commas, quotes, and newlines")
    func csvEscaping() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, nameField, _) = makeSampleCatalogue(in: ctx)

        let item = CatalogueItem(isWishlist: true, notes: "line one\nline two")
        item.createdDate = Date.now.addingTimeInterval(60) // sorts after the sample item
        item.catalogue = catalogue
        ctx.insert(item)

        let fv = FieldValue(fieldDefinition: nameField, fieldType: .text)
        fv.textValue = #"Hawker "Hurricane", MkI"#
        fv.item = item
        ctx.insert(fv)

        let csv = CatalogueExporter.csvString(for: catalogue)
        #expect(csv.contains(#""Hawker ""Hurricane"", MkI""#), "Quotes doubled and cell wrapped in quotes")
        #expect(csv.contains("\"line one\nline two\""), "Newline cell wrapped in quotes")
        #expect(csv.contains("Wishlist"))
    }

    @Test("CSV excludes soft-deleted items")
    func csvExcludesSoftDeleted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _) = makeSampleCatalogue(in: ctx)

        let deleted = CatalogueItem(isWishlist: false, notes: "gone")
        deleted.deletedDate = Date.now
        deleted.catalogue = catalogue
        ctx.insert(deleted)

        let csv = CatalogueExporter.csvString(for: catalogue)
        #expect(csv.components(separatedBy: "\n").count == 2, "Header plus one active item")
        #expect(csv.contains("gone") == false)
    }

    @Test("CSV numbers are exported without grouping separators")
    func csvNumberNoGrouping() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, yearField) = makeSampleCatalogue(in: ctx)

        let item = CatalogueItem(isWishlist: false)
        item.createdDate = Date.now.addingTimeInterval(60)
        item.catalogue = catalogue
        ctx.insert(item)

        let fv = FieldValue(fieldDefinition: yearField, fieldType: .number)
        fv.numberValue = 1_234_567
        fv.item = item
        ctx.insert(fv)

        #expect(CatalogueExporter.csvString(for: catalogue).contains("1234567"))
    }

    // MARK: - JSON

    @Test("JSON export decodes as version 1 with full catalogue content")
    func jsonExportStructure() throws {
        let container = try makeContainer()
        let (catalogue, _, _) = makeSampleCatalogue(in: container.mainContext)

        let data = try CatalogueExporter.jsonData(for: catalogue)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(CatalogueExportFile.self, from: data)

        #expect(file.version == 1)
        let dto = try #require(file.catalogues.first)
        #expect(dto.name == "Planes")
        #expect(dto.fieldDefinitions.map(\.name) == ["Name", "Year"])
        #expect(dto.items.count == 1)
        #expect(dto.items.first?.fieldValues.count == 2)
    }

    @Test("JSON export with includePhotos false omits photo data")
    func jsonExportWithoutPhotos() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _) = makeSampleCatalogue(in: ctx)

        let item = try #require(catalogue.items.first)
        let photo = ItemPhoto(imageData: Data([0xFF, 0xD8, 0xFF]), priority: 0, caption: "Box art")
        photo.item = item
        ctx.insert(photo)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let withPhotos = try decoder.decode(
            CatalogueExportFile.self,
            from: CatalogueExporter.jsonData(for: catalogue, includePhotos: true)
        )
        #expect(withPhotos.catalogues.first?.items.first?.photos.count == 1)

        let withoutPhotos = try decoder.decode(
            CatalogueExportFile.self,
            from: CatalogueExporter.jsonData(for: catalogue, includePhotos: false)
        )
        #expect(withoutPhotos.catalogues.first?.items.first?.photos.isEmpty == true)
    }

    @Test("JSON export excludes soft-deleted items")
    func jsonExportExcludesSoftDeleted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _) = makeSampleCatalogue(in: ctx)

        let deleted = CatalogueItem(isWishlist: false)
        deleted.deletedDate = Date.now
        deleted.catalogue = catalogue
        ctx.insert(deleted)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(
            CatalogueExportFile.self,
            from: CatalogueExporter.jsonData(for: catalogue)
        )
        #expect(file.catalogues.first?.items.count == 1)
    }

    // MARK: - Round Trip

    @Test("Export then import reproduces the catalogue, fields, items, and search text")
    func exportImportRoundTrip() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (original, _, _) = makeSampleCatalogue(in: ctx)

        let data = try CatalogueExporter.jsonData(for: original)
        let imported = try await CatalogueImporter.importCatalogues(
            from: data,
            into: ctx,
            priorityOffset: 1
        )

        let copy = try #require(imported.first)
        #expect(copy.name == original.name)
        #expect(copy.iconName == original.iconName)
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
}
