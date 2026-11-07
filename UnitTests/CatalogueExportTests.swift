//
//  CatalogueExportTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
import UniformTypeIdentifiers
@testable import catalogue_it

// MARK: - Catalogue Export Tests

/// Tests JSON export (including a full export → import round trip) and the share sheet providers.
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

    // MARK: - JSON

    @Test("JSON export decodes as the current version with full catalogue content")
    func jsonExportStructure() throws {
        let container = try makeContainer()
        let (catalogue, _, _) = makeSampleCatalogue(in: container.mainContext)

        let data = try CatalogueExporter.jsonData(for: catalogue)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(CatalogueExportFile.self, from: data)

        #expect(file.version == CatalogueExportFile.currentVersion)
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

        let deleted = CatalogueItem()
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
        original.icon = .photo(Data([0xFF, 0xD8, 0xFF, 0x01]))

        let data = try CatalogueExporter.jsonData(for: original)
        let imported = try await CatalogueImporter.importCatalogues(
            from: data,
            into: ctx,
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

    // MARK: - Share Sheet

    /// Loads what a share destination would receive: the system asks the provider for data on
    /// a queue of its own, not the main actor.
    private func loadData(from provider: NSItemProvider, as type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    @Test("Every Back Up entry hands the share sheet a named, loadable file", arguments: CatalogueExportFormat.allCases)
    func shareSheetItemProvider(format: CatalogueExportFormat) async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _) = makeSampleCatalogue(in: ctx)
        let item = try #require(catalogue.items.first)
        let photo = ItemPhoto(imageData: Data([0xFF, 0xD8, 0xFF]), priority: 0)
        photo.item = item
        ctx.insert(photo)
        try ctx.save() // the file's writer reads the catalogue by identifier, from its own context

        let provider = format.itemProvider(for: catalogue)
        #expect(provider.registeredTypeIdentifiers == [UTType.json.identifier])
        #expect(provider.suggestedName == format.filename(for: catalogue))

        let data = try await loadData(from: provider, as: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(CatalogueExportFile.self, from: data)
        let photos = try #require(file.catalogues.first?.items.first?.photos)
        #expect(photos.count == (format == .jsonWithPhotos ? 1 : 0))
        withExtendedLifetime(container) {}
    }
}
