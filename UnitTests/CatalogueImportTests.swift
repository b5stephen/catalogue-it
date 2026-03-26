//
//  CatalogueImportTests.swift
//  UnitTests
//
//  Created by Stephen Denekamp on 26/03/2026.
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Import Tests

/// Tests that a static JSON fixture representing the v1 schema imports correctly.
///
/// The fixture is intentionally a literal string — not generated programmatically —
/// so it stays representative of a real export file produced at a point in time.
/// When a future schema change breaks import of old files, exactly one of these
/// tests will fail, pointing to the regression.
@MainActor
struct CatalogueImportTests {

    // MARK: - Fixture Constants

    private static let manufacturerFieldID = "00000000-0000-0000-0000-000000000001"
    private static let yearFieldID         = "00000000-0000-0000-0000-000000000002"
    private static let acquiredFieldID     = "00000000-0000-0000-0000-000000000003"
    private static let paintedFieldID      = "00000000-0000-0000-0000-000000000004"

    /// A 1×1 transparent PNG in base64. Used as the photo payload in the fixture.
    private static let photoBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    /// Static v1 export representing the schema as of March 2026.
    /// Contains: 1 catalogue, 4 field definitions (one of each type), 2 items,
    /// field values of every type, and 1 photo on the owned item.
    private static let v1JSON = """
    {
      "version": 1,
      "exportedAt": "2026-03-26T10:00:00Z",
      "catalogues": [
        {
          "name": "Model Planes",
          "iconName": "airplane",
          "colorHex": "#007AFF",
          "createdDate": "2026-01-01T09:00:00Z",
          "priority": 0,
          "sortFieldKey": "\(manufacturerFieldID)",
          "sortDirection": "asc",
          "fieldDefinitions": [
            {
              "fieldID": "\(manufacturerFieldID)",
              "name": "Manufacturer",
              "fieldType": "Text",
              "priority": 0
            },
            {
              "fieldID": "\(yearFieldID)",
              "name": "Year",
              "fieldType": "Number",
              "priority": 1,
              "fieldOptions": { "number": { "_0": { "format": "Number", "precision": 0 } } }
            },
            {
              "fieldID": "\(acquiredFieldID)",
              "name": "Acquired",
              "fieldType": "Date",
              "priority": 2
            },
            {
              "fieldID": "\(paintedFieldID)",
              "name": "Painted",
              "fieldType": "Yes/No",
              "priority": 3
            }
          ],
          "items": [
            {
              "createdDate": "2026-01-10T08:00:00Z",
              "isWishlist": false,
              "notes": "My first model",
              "fieldValues": [
                { "fieldDefinitionID": "\(manufacturerFieldID)", "fieldType": "Text", "textValue": "Airfix" },
                { "fieldDefinitionID": "\(yearFieldID)", "fieldType": "Number", "numberValue": 1969 },
                { "fieldDefinitionID": "\(acquiredFieldID)", "fieldType": "Date", "dateValue": "2026-01-05T00:00:00Z" },
                { "fieldDefinitionID": "\(paintedFieldID)", "fieldType": "Yes/No", "boolValue": true }
              ],
              "photos": [
                { "imageData": "\(photoBase64)", "priority": 0, "caption": "Front view" }
              ]
            },
            {
              "createdDate": "2026-01-12T09:00:00Z",
              "isWishlist": true,
              "fieldValues": [
                { "fieldDefinitionID": "\(manufacturerFieldID)", "fieldType": "Text", "textValue": "Tamiya" }
              ],
              "photos": []
            }
          ]
        }
      ]
    }
    """

    // MARK: - Helper

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func importFixture(priorityOffset: Int = 0) throws -> (container: ModelContainer, catalogues: [Catalogue]) {
        let container = try makeContainer()
        let data = try #require(Self.v1JSON.data(using: .utf8))
        let catalogues = try CatalogueImporter.importCatalogues(
            from: data,
            into: container.mainContext,
            priorityOffset: priorityOffset
        )
        return (container, catalogues)
    }

    // MARK: - Tests

    @Test("Catalogue metadata is imported correctly")
    func importCatalogueMetadata() throws {
        let (container, catalogues) = try importFixture(priorityOffset: 2)
        #expect(catalogues.count == 1)
        let catalogue = try #require(catalogues.first)
        #expect(catalogue.name == "Model Planes")
        #expect(catalogue.iconName == "airplane")
        #expect(catalogue.colorHex == "#007AFF")
        #expect(catalogue.priority == 2)  // 0 from fixture + 2 priority offset
        let expectedDate = try #require(ISO8601DateFormatter().date(from: "2026-01-01T09:00:00Z"))
        #expect(catalogue.createdDate == expectedDate)
        _ = container
    }

    @Test("Field definitions are imported with correct names, types, and options")
    func importFieldDefinitions() throws {
        let (container, catalogues) = try importFixture()
        let catalogue = try #require(catalogues.first)
        let defs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
        #expect(defs.count == 4)
        #expect(defs[0].name == "Manufacturer"); #expect(defs[0].fieldType == .text);    #expect(defs[0].fieldOptions == nil)
        #expect(defs[1].name == "Year");         #expect(defs[1].fieldType == .number);  #expect(defs[1].numberOptions == NumberOptions(format: .number, precision: 0))
        #expect(defs[2].name == "Acquired");     #expect(defs[2].fieldType == .date);    #expect(defs[2].fieldOptions == nil)
        #expect(defs[3].name == "Painted");      #expect(defs[3].fieldType == .boolean); #expect(defs[3].fieldOptions == nil)
        _ = container
    }

    @Test("Items are imported with correct isWishlist flag and notes")
    func importItems() throws {
        let (container, catalogues) = try importFixture()
        let catalogue = try #require(catalogues.first)
        let items = catalogue.items.sorted { $0.createdDate < $1.createdDate }
        #expect(items.count == 2)
        #expect(items[0].isWishlist == false)
        #expect(items[0].notes == "My first model")
        #expect(items[1].isWishlist == true)
        #expect(items[1].notes == nil)
        _ = container
    }

    @Test("All four field value types decode correctly")
    func importFieldValues() throws {
        let (container, catalogues) = try importFixture()
        let catalogue = try #require(catalogues.first)
        let ownedItem = try #require(catalogue.items.first { !$0.isWishlist })

        let textFV = try #require(ownedItem.fieldValues.first { $0.fieldType == .text })
        #expect(textFV.textValue == "Airfix")

        let numberFV = try #require(ownedItem.fieldValues.first { $0.fieldType == .number })
        #expect(numberFV.numberValue == 1969)

        let dateFV = try #require(ownedItem.fieldValues.first { $0.fieldType == .date })
        let expectedDate = try #require(ISO8601DateFormatter().date(from: "2026-01-05T00:00:00Z"))
        #expect(dateFV.dateValue == expectedDate)

        let boolFV = try #require(ownedItem.fieldValues.first { $0.fieldType == .boolean })
        #expect(boolFV.boolValue == true)
        _ = container
    }

    @Test("Photos are imported with correct data, priority, and caption")
    func importPhotos() throws {
        let (container, catalogues) = try importFixture()
        let catalogue = try #require(catalogues.first)
        let ownedItem    = try #require(catalogue.items.first { !$0.isWishlist })
        let wishlistItem = try #require(catalogue.items.first { $0.isWishlist })

        #expect(ownedItem.photos.count == 1)
        #expect(wishlistItem.photos.count == 0)

        let photo = try #require(ownedItem.photos.first)
        #expect(photo.priority == 0)
        #expect(photo.caption == "Front view")
        let expectedData = try #require(Data(base64Encoded: Self.photoBase64))
        #expect(photo.imageData == expectedData)
        _ = container
    }

    @Test("sortFieldKey UUID reference is preserved verbatim after import")
    func importSortKeyPreserved() throws {
        let (container, catalogues) = try importFixture()
        let catalogue = try #require(catalogues.first)
        let manufacturerDef = try #require(catalogue.fieldDefinitions.first { $0.name == "Manufacturer" })
        // sortFieldKey must match the fieldID of the Manufacturer definition so that
        // the sort preference continues to resolve after import.
        #expect(catalogue.sortFieldKey == manufacturerDef.fieldID.uuidString)
        _ = container
    }

    @Test("Unsupported version throws ImportError.unsupportedVersion with correct version number")
    func importUnsupportedVersion() throws {
        let container = try makeContainer()
        let badJSON = #"{"version":99,"exportedAt":"2026-03-26T10:00:00Z","catalogues":[]}"#
        let data = try #require(badJSON.data(using: .utf8))
        #expect {
            try CatalogueImporter.importCatalogues(
                from: data,
                into: container.mainContext,
                priorityOffset: 0
            )
        } throws: { error in
            guard case CatalogueImporter.ImportError.unsupportedVersion(let v) = error else { return false }
            return v == 99
        }
    }

    @Test("Field values referencing unknown definitions are skipped silently")
    func importOrphanedFieldValueSkipped() throws {
        let container = try makeContainer()
        let json = #"""
        {
          "version": 1,
          "exportedAt": "2026-03-26T10:00:00Z",
          "catalogues": [{
            "name": "Test", "iconName": "star", "colorHex": "#000000",
            "createdDate": "2026-01-01T00:00:00Z", "priority": 0,
            "sortFieldKey": "__dateAdded", "sortDirection": "asc",
            "fieldDefinitions": [],
            "items": [{
              "createdDate": "2026-01-02T00:00:00Z",
              "isWishlist": false,
              "fieldValues": [{
                "fieldDefinitionID": "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
                "fieldType": "Text",
                "textValue": "Orphan"
              }],
              "photos": []
            }]
          }]
        }
        """#
        let data = try #require(json.data(using: .utf8))
        let catalogues = try CatalogueImporter.importCatalogues(
            from: data,
            into: container.mainContext,
            priorityOffset: 0
        )
        let item = try #require(catalogues.first?.items.first)
        #expect(item.fieldValues.isEmpty)
    }
}
