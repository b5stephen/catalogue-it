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

    private func importFixture(priorityOffset: Int = 0) async throws -> (container: ModelContainer, catalogues: [Catalogue]) {
        let container = try makeContainer()
        let data = try #require(Self.v1JSON.data(using: .utf8))
        let catalogues = try await CatalogueImporter.importCatalogues(
            from: data,
            into: container.mainContext,
            priorityOffset: priorityOffset
        )
        return (container, catalogues)
    }

    // MARK: - Tests

    @Test("Catalogue metadata is imported correctly")
    func importCatalogueMetadata() async throws {
        let (container, catalogues) = try await importFixture(priorityOffset: 2)
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
    func importFieldDefinitions() async throws {
        let (container, catalogues) = try await importFixture()
        let catalogue = try #require(catalogues.first)
        let defs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
        // 4 from the file, plus the Status field synthesised from the legacy isWishlist flags.
        #expect(defs.count == 5)
        #expect(defs[0].name == "Manufacturer"); #expect(defs[0].fieldType == .text);    #expect(defs[0].fieldOptions == nil)
        #expect(defs[1].name == "Year");         #expect(defs[1].fieldType == .number);  #expect(defs[1].numberOptions == NumberOptions(format: .number, precision: 0))
        #expect(defs[2].name == "Acquired");     #expect(defs[2].fieldType == .date);    #expect(defs[2].fieldOptions == nil)
        #expect(defs[3].name == "Painted");      #expect(defs[3].fieldType == .boolean); #expect(defs[3].fieldOptions == nil)
        _ = container
    }

    @Test("Items are imported with notes and migrated status")
    func importItems() async throws {
        let (container, catalogues) = try await importFixture()
        let catalogue = try #require(catalogues.first)
        let items = catalogue.items.sorted { $0.createdDate < $1.createdDate }
        #expect(items.count == 2)
        #expect(items[0].statusValue == LegacyWishlistUpgrade.ownedOption)
        #expect(items[0].notes == "My first model")
        #expect(items[1].statusValue == LegacyWishlistUpgrade.wishlistOption)
        #expect(items[1].notes == nil)
        _ = container
    }

    // MARK: - v1 Wishlist Upgrade

    @Test("A v1 file gains a status field driving the tab bar")
    func v1SynthesisesStatusField() async throws {
        let (container, catalogues) = try await importFixture()
        let catalogue = try #require(catalogues.first)

        let statusField = try #require(catalogue.statusField)
        #expect(statusField.name == LegacyWishlistUpgrade.statusFieldName)
        #expect(statusField.fieldType == .optionList)
        #expect(statusField.displayRole == .statusTabs)
        #expect(statusField.optionListOptions?.options == ["Owned", "Wishlist"])
        #expect(statusField.optionListOptions?.defaultValue == "Owned")
        // Appended after the file's own fields, so it doesn't displace the display-name field.
        #expect(statusField.priority == 4)
        _ = container
    }

    @Test("Migrated status exists as a real field value, not only a denormalised column")
    func v1StatusIsBackedByFieldValues() async throws {
        let (container, catalogues) = try await importFixture()
        let catalogue = try #require(catalogues.first)
        let statusField = try #require(catalogue.statusField)

        for item in catalogue.items {
            let fv = try #require(item.value(for: statusField))
            #expect(fv.fieldType == .optionList)
            #expect(fv.textValue == item.statusValue)
        }
        _ = container
    }

    @Test("The synthesised status field produces working tabs")
    func v1StatusProducesTabs() async throws {
        let (container, catalogues) = try await importFixture()
        let catalogue = try #require(catalogues.first)

        let labels = catalogue.statusTabDescriptors.map(\.label)
        #expect(labels == ["All", "Owned", "Wishlist"])
        _ = container
    }

    @Test("Import is idempotent in shape — re-exporting a migrated catalogue needs no second upgrade")
    func migratedCatalogueExportsAsV2() async throws {
        let (container, catalogues) = try await importFixture()
        let catalogue = try #require(catalogues.first)

        let dto = CatalogueDTO(catalogue)
        // Round-tripping must not re-trigger the upgrade: the status field now describes itself.
        #expect(dto.items.allSatisfy { $0.isWishlist == nil })
        #expect(LegacyWishlistUpgrade.synthesisedStatusField(for: dto) == nil)
        _ = container
    }

    @Test("A status field named Status already in the file is not duplicated")
    func v1AvoidsNameCollision() async throws {
        let container = try makeContainer()
        let json = #"""
        {
          "version": 1,
          "exportedAt": "2026-03-26T10:00:00Z",
          "catalogues": [{
            "name": "Test", "iconName": "star", "colorHex": "#000000",
            "createdDate": "2026-01-01T00:00:00Z", "priority": 0,
            "sortFieldKey": "__dateAdded", "sortDirection": "asc",
            "fieldDefinitions": [{
              "fieldID": "00000000-0000-0000-0000-0000000000AA",
              "name": "Status", "fieldType": "Text", "priority": 0
            }],
            "items": [{
              "createdDate": "2026-01-02T00:00:00Z",
              "isWishlist": true,
              "fieldValues": [],
              "photos": []
            }]
          }]
        }
        """#
        let data = try #require(json.data(using: .utf8))
        let catalogues = try await CatalogueImporter.importCatalogues(
            from: data, into: container.mainContext, priorityOffset: 0
        )
        let catalogue = try #require(catalogues.first)
        let statusField = try #require(catalogue.statusField)
        // The user's own "Status" text field keeps its name; the synthesised one steps aside.
        #expect(statusField.name == "Status 2")
        #expect(catalogue.fieldDefinitions.count == 2)
    }

    @Test("A v2 file is imported as-is with no upgrade applied")
    func v2ImportsWithoutUpgrade() async throws {
        let container = try makeContainer()
        let json = #"""
        {
          "version": 2,
          "exportedAt": "2026-08-01T10:00:00Z",
          "catalogues": [{
            "name": "Films", "iconName": "film", "colorHex": "#000000",
            "createdDate": "2026-01-01T00:00:00Z", "priority": 0,
            "sortFieldKey": "__dateAdded", "sortDirection": "asc",
            "showAllTab": false,
            "fieldDefinitions": [
              {
                "fieldID": "00000000-0000-0000-0000-0000000000B1",
                "name": "Seen", "fieldType": "Yes/No", "priority": 0,
                "displayRole": "statusTabs",
                "fieldOptions": { "boolean": { "_0": { "trueLabel": "Watched", "falseLabel": "Unwatched", "defaultValue": false } } }
              },
              {
                "fieldID": "00000000-0000-0000-0000-0000000000B2",
                "name": "Favourite", "fieldType": "Yes/No", "priority": 1,
                "displayRole": "flagFilter"
              }
            ],
            "items": [{
              "createdDate": "2026-01-02T00:00:00Z",
              "fieldValues": [
                { "fieldDefinitionID": "00000000-0000-0000-0000-0000000000B1", "fieldType": "Yes/No", "boolValue": true },
                { "fieldDefinitionID": "00000000-0000-0000-0000-0000000000B2", "fieldType": "Yes/No", "boolValue": true }
              ],
              "photos": []
            }]
          }]
        }
        """#
        let data = try #require(json.data(using: .utf8))
        let catalogues = try await CatalogueImporter.importCatalogues(
            from: data, into: container.mainContext, priorityOffset: 0
        )
        let catalogue = try #require(catalogues.first)
        #expect(catalogue.showAllTab == false)
        #expect(catalogue.fieldDefinitions.count == 2, "No status field should be synthesised")

        let statusField = try #require(catalogue.statusField)
        #expect(statusField.name == "Seen")
        #expect(statusField.statusTabLabels.trueLabel == "Watched")
        #expect(statusField.statusTabLabels.falseLabel == "Unwatched")
        #expect(catalogue.statusTabDescriptors.map(\.label) == ["Watched", "Unwatched"], "showAllTab is off")

        #expect(catalogue.flagFields.map(\.name) == ["Favourite"])

        let item = try #require(catalogue.items.first)
        #expect(item.statusValue == ItemFacetBuilder.boolTrueToken)
        let favourite = try #require(catalogue.flagFields.first)
        #expect(item.flagKeys.contains(ItemFacetBuilder.flagToken(for: favourite.fieldID)))
    }

    @Test("A display role the field type cannot support is reset on import")
    func invalidDisplayRoleIsReset() async throws {
        let container = try makeContainer()
        // A text field claiming statusTabs — hand-edited or written by a newer build.
        let json = #"""
        {
          "version": 2,
          "exportedAt": "2026-08-01T10:00:00Z",
          "catalogues": [{
            "name": "Test", "iconName": "star", "colorHex": "#000000",
            "createdDate": "2026-01-01T00:00:00Z", "priority": 0,
            "sortFieldKey": "__dateAdded", "sortDirection": "asc",
            "fieldDefinitions": [{
              "fieldID": "00000000-0000-0000-0000-0000000000C1",
              "name": "Title", "fieldType": "Text", "priority": 0,
              "displayRole": "statusTabs"
            }],
            "items": []
          }]
        }
        """#
        let data = try #require(json.data(using: .utf8))
        let catalogues = try await CatalogueImporter.importCatalogues(
            from: data, into: container.mainContext, priorityOffset: 0
        )
        let catalogue = try #require(catalogues.first)
        #expect(catalogue.fieldDefinitions.first?.displayRole == DisplayRole.none)
        #expect(catalogue.statusField == nil)
        #expect(catalogue.statusTabDescriptors.isEmpty)
    }

    @Test("All four field value types decode correctly")
    func importFieldValues() async throws {
        let (container, catalogues) = try await importFixture()
        let catalogue = try #require(catalogues.first)
        let ownedItem = try #require(catalogue.items.first { $0.statusValue == LegacyWishlistUpgrade.ownedOption })

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
    func importPhotos() async throws {
        let (container, catalogues) = try await importFixture()
        let catalogue = try #require(catalogues.first)
        let ownedItem    = try #require(catalogue.items.first { $0.statusValue == LegacyWishlistUpgrade.ownedOption })
        let wishlistItem = try #require(catalogue.items.first { $0.statusValue == LegacyWishlistUpgrade.wishlistOption })

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
    func importSortKeyPreserved() async throws {
        let (container, catalogues) = try await importFixture()
        let catalogue = try #require(catalogues.first)
        let manufacturerDef = try #require(catalogue.fieldDefinitions.first { $0.name == "Manufacturer" })
        // sortFieldKey must match the fieldID of the Manufacturer definition so that
        // the sort preference continues to resolve after import.
        #expect(catalogue.sortFieldKey == manufacturerDef.fieldID.uuidString)
        _ = container
    }

    @Test("Unsupported version throws ImportError.unsupportedVersion with correct version number")
    func importUnsupportedVersion() async throws {
        let container = try makeContainer()
        let badJSON = #"{"version":99,"exportedAt":"2026-03-26T10:00:00Z","catalogues":[]}"#
        let data = try #require(badJSON.data(using: .utf8))
        await #expect {
            _ = try await CatalogueImporter.importCatalogues(
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
    func importOrphanedFieldValueSkipped() async throws {
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
        let catalogues = try await CatalogueImporter.importCatalogues(
            from: data,
            into: container.mainContext,
            priorityOffset: 0
        )
        let catalogue = try #require(catalogues.first)
        let item = try #require(catalogue.items.first)

        // The file's only field value points at a definition that doesn't exist, so it is
        // dropped. The one value that remains is the status migrated from `isWishlist`.
        let statusField = try #require(catalogue.statusField)
        #expect(item.fieldValues.count == 1)
        #expect(item.value(for: statusField) != nil)
        #expect(!item.fieldValues.contains { $0.textValue == "Orphan" })
    }
}
