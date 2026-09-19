//
//  SchemaMigrationTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Schema Migration Tests

/// Opens a store written at schema V1 with the live schema and the migration plan — the
/// path every device that installed a pre-`modifiedDate` build takes on first launch of the
/// next one. On disk, because a migration is a property of the store file, not the context.
///
/// Serialized: each test writes its own file, but the V1 model classes register with the
/// same entity names as the live ones, and concurrent container builds have been seen to
/// trip over each other.
@Suite(.serialized)
@MainActor
struct SchemaMigrationTests {

    private func makeStoreURL() -> URL {
        URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString).store")
    }

    /// Removes the store and its SQLite sidecars once a test is done with it.
    private func removeStore(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path + suffix))
        }
    }

    /// Writes a V1 store with one catalogue, one field and `count` items, each created at a
    /// distinct date well in the past. Returns the created dates keyed by note so the
    /// migrated rows can be matched up without relying on identifiers.
    private func writeV1Store(at url: URL, itemCount count: Int) throws -> [String: Date] {
        let container = try ModelContainer(
            for: Schema(versionedSchema: CatalogueSchemaV1.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = container.mainContext

        let catalogue = CatalogueSchemaV1.Catalogue(name: "Films", iconName: "film", colorHex: "#112233")
        context.insert(catalogue)
        let title = CatalogueSchemaV1.FieldDefinition(name: "Title", fieldType: .text, priority: 0)
        context.insert(title)
        title.catalogue = catalogue

        var createdDates: [String: Date] = [:]
        for index in 0..<count {
            let item = CatalogueSchemaV1.CatalogueItem(notes: "item-\(index)")
            item.createdDate = Date(timeIntervalSince1970: 1_600_000_000 + Double(index) * 86_400)
            item.searchText = "film \(index)"
            context.insert(item)
            item.catalogue = catalogue

            let value = CatalogueSchemaV1.FieldValue(fieldDefinition: nil, fieldType: .text)
            value.textValue = "Film \(index)"
            context.insert(value)
            value.fieldDefinition = title
            value.item = item

            let photo = CatalogueSchemaV1.ItemPhoto(imageData: Data([0xFF, 0xD8, 0xFF, UInt8(index)]), priority: 0, caption: "cover")
            context.insert(photo)
            photo.item = item

            createdDates["item-\(index)"] = item.createdDate
        }
        try context.save()
        return createdDates
    }

    private func openCurrent(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: CatalogueSchemaCurrent.self),
            migrationPlan: CatalogueMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
    }

    // MARK: - Tests

    @Test func v1StoreOpensUnderTheCurrentSchemaWithEveryRowIntact() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }
        let createdDates = try writeV1Store(at: url, itemCount: 3)

        let container = try openCurrent(at: url)
        let context = container.mainContext

        let catalogues = try context.fetch(FetchDescriptor<Catalogue>())
        #expect(catalogues.count == 1)
        #expect(catalogues.first?.name == "Films")
        #expect(catalogues.first?.fieldDefinitions.count == 1)

        let items = try context.fetch(FetchDescriptor<CatalogueItem>())
        #expect(items.count == createdDates.count)
        for item in items {
            let note = try #require(item.notes)
            #expect(item.createdDate == createdDates[note])
            #expect(item.fieldValues.count == 1)
            #expect(item.fieldValues.first?.textValue?.hasPrefix("Film ") == true)
            #expect(item.fieldValues.first?.fieldDefinition?.name == "Title")
            #expect(item.photos.count == 1)
            #expect(item.photos.first?.caption == "cover")
        }
    }

    @Test func migratedItemsGetModifiedDateEqualToCreatedDate() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }
        let createdDates = try writeV1Store(at: url, itemCount: 5)
        let migrationStarted = Date.now

        let container = try openCurrent(at: url)
        let items = try container.mainContext.fetch(FetchDescriptor<CatalogueItem>())

        #expect(items.count == 5)
        for item in items {
            let note = try #require(item.notes)
            #expect(item.modifiedDate == createdDates[note],
                    "an item nobody has edited must not read as modified at migration time")
            #expect(item.modifiedDate < migrationStarted)
        }
    }

    @Test func migratedStoreIsCleanAndReopensWithoutMigratingAgain() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }
        let createdDates = try writeV1Store(at: url, itemCount: 2)

        do {
            let container = try openCurrent(at: url)
            #expect(!container.mainContext.hasChanges, "the backfill must have been saved")
        }

        // Second launch: the store is already at V2. Nothing should move.
        let container = try openCurrent(at: url)
        let items = try container.mainContext.fetch(FetchDescriptor<CatalogueItem>())
        #expect(items.count == 2)
        for item in items {
            #expect(item.modifiedDate == createdDates[try #require(item.notes)])
        }
    }

    @Test func itemsCreatedAfterMigrationAreEditableInPlace() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }
        _ = try writeV1Store(at: url, itemCount: 1)

        let container = try openCurrent(at: url)
        let context = container.mainContext
        let catalogue = try #require(try context.fetch(FetchDescriptor<Catalogue>()).first)
        let item = try #require(try context.fetch(FetchDescriptor<CatalogueItem>()).first)
        let title = try #require(catalogue.fieldDefinitions.first)
        let valueID = try #require(item.fieldValues.first).persistentModelID
        let stamp = Date(timeIntervalSince1970: 1_900_000_000)

        // A migrated item goes through the same save path as any other.
        var draft = FieldValueDraft(fieldDefinition: title, fieldType: .text)
        draft.textValue = "Renamed after migration"
        let outcome = try ItemSaveService.save(
            existing: item, in: catalogue, notes: item.notes ?? "",
            fieldDrafts: [draft],
            photoDrafts: item.photos.map {
                PhotoDraft(imageData: $0.imageData, caption: $0.caption ?? "", priority: $0.priority,
                           existingPhotoID: $0.persistentModelID)
            },
            context: context, now: stamp
        )

        #expect(outcome.fieldsChanged)
        #expect(!outcome.photosChanged)
        #expect(item.fieldValues.first?.persistentModelID == valueID)
        #expect(item.fieldValues.first?.textValue == "Renamed after migration")
        #expect(item.modifiedDate == stamp)
    }

    @Test func schemaVersionsAreOrderedAndTheCurrentOneIsLast() {
        let versions = CatalogueMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions == [Schema.Version(1, 0, 0), Schema.Version(2, 0, 0)])
        #expect(CatalogueSchemaCurrent.versionIdentifier == versions.last)
        #expect(CatalogueMigrationPlan.stages.count == versions.count - 1)
    }

    @Test func frozenV1AndCurrentSchemaShareEntityNames() {
        let v1 = Set(CatalogueSchemaV1.models.map { String(describing: $0) })
        let current = Set(CatalogueSchemaCurrent.models.map { String(describing: $0) })
        #expect(v1 == current, "a migration stage can only map entities that exist on both sides")
    }
}
