//
//  ExistingCatalogueImportTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

/// Importing a Data file's catalogue into one that already exists, through `ItemImporter`.
@MainActor
struct ExistingCatalogueImportTests {

    private static let existingDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let newDate = Date(timeIntervalSince1970: 1_700_100_000)

    private struct Target {
        let container: ModelContainer
        let catalogue: Catalogue
        let name: FieldDefinition
        let scale: FieldDefinition
        let item: CatalogueItem
    }

    /// "Planes": Name (text), Scale (option list "1:48"), and one item, Spitfire.
    private func makeTarget() throws -> Target {
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Planes")
        ctx.insert(catalogue)
        let name = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        ctx.insert(name)
        name.catalogue = catalogue
        let scale = FieldDefinition(name: "Scale", fieldType: .optionList, priority: 1)
        ctx.insert(scale)
        scale.catalogue = catalogue
        scale.optionListOptions = OptionListOptions(options: ["1:48"])

        let item = CatalogueItem()
        ctx.insert(item)
        item.catalogue = catalogue
        item.createdDate = Self.existingDate
        let value = FieldValue(fieldDefinition: nil, fieldType: .text)
        ctx.insert(value)
        value.fieldDefinition = name
        value.textValue = "Spitfire"
        value.item = item
        ItemDerivedColumns.refresh(on: item, fieldValues: [value], definitions: catalogue.sortedFieldDefinitions)
        try ctx.save()
        return Target(container: container, catalogue: catalogue, name: name, scale: scale, item: item)
    }

    private static let fileName = UUID()
    private static let fileScale = UUID()
    private static let filePrice = UUID()
    private static let fileStatus = UUID()

    /// Another device's "Planes": Name and Scale under other IDs, plus Price and a status field.
    /// One item duplicates the target's Spitfire; the other is new, in a scale the target lacks.
    private func makeFile() -> CatalogueDTO {
        func value(_ field: UUID, _ type: FieldType, text: String? = nil, number: Double? = nil, bool: Bool? = nil) -> FieldValueDTO {
            FieldValueDTO(fieldDefinitionID: field, fieldType: type, textValue: text, numberValue: number, dateValue: nil, boolValue: bool)
        }
        return CatalogueDTO(
            name: "Planes", iconName: "airplane", iconImageData: nil, iconImageKind: nil, colorHex: "#FF0000",
            createdDate: .now, priority: 0, sortFieldKey: "", sortDirection: "", showAllTab: false,
            fieldDefinitions: [
                FieldDefinitionDTO(fieldID: Self.fileName, name: "name", fieldType: .text, priority: 0, fieldOptions: nil, displayRole: nil),
                FieldDefinitionDTO(fieldID: Self.fileScale, name: "Scale", fieldType: .optionList, priority: 1,
                                   fieldOptions: .optionList(OptionListOptions(options: ["1:72"])), displayRole: nil),
                FieldDefinitionDTO(fieldID: Self.filePrice, name: "Price", fieldType: .number, priority: 2, fieldOptions: nil, displayRole: nil),
                FieldDefinitionDTO(fieldID: Self.fileStatus, name: "Built", fieldType: .boolean, priority: 3,
                                   fieldOptions: nil, displayRole: .statusTabs),
            ],
            items: [
                CatalogueItemDTO(createdDate: Self.existingDate, modifiedDate: nil, isWishlist: nil, notes: nil,
                                 fieldValues: [value(Self.fileName, .text, text: "Spitfire")], photos: []),
                CatalogueItemDTO(createdDate: Self.newDate, modifiedDate: nil, isWishlist: nil, notes: "Gift",
                                 fieldValues: [
                                    value(Self.fileName, .text, text: "Hurricane"),
                                    value(Self.fileScale, .optionList, text: "1:72"),
                                    value(Self.filePrice, .number, number: 12.5),
                                    value(Self.fileStatus, .boolean, bool: true),
                                 ], photos: []),
            ]
        )
    }

    private func runImport(_ file: CatalogueDTO, into target: Target, skippingDuplicates: Bool = true) async throws -> ImportSummary {
        let container = target.container
        let catalogueID = target.catalogue.persistentModelID
        return try await Task.detached {
            try await ItemImporter(modelContainer: container)
                .importCatalogue(file, into: catalogueID, skippingDuplicates: skippingDuplicates)
        }.value
    }

    private func liveItems(_ target: Target) throws -> [CatalogueItem] {
        let catalogueID = target.catalogue.persistentModelID
        return try target.container.mainContext.fetch(FetchDescriptor<CatalogueItem>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID && $0.deletedDate == nil },
            sortBy: [SortDescriptor(\.createdDate)]))
    }

    private func definitions(_ target: Target) throws -> [FieldDefinition] {
        let catalogueID = target.catalogue.persistentModelID
        return try target.container.mainContext.fetch(FetchDescriptor<FieldDefinition>(
            predicate: #Predicate { $0.catalogue?.persistentModelID == catalogueID }))
            .sorted(by: FieldDefinition.isOrderedBefore)
    }

    // MARK: - Tests

    @Test("Matching fields are reused, the rest added after the catalogue's own")
    func fieldsMatchedAndAdded() async throws {
        let target = try makeTarget()
        let summary = try await runImport(makeFile(), into: target)

        let defs = try definitions(target)
        #expect(defs.map(\.name) == ["Name", "Scale", "Price", "Built"])
        #expect(defs.map(\.priority) == [0, 1, 2, 3])
        #expect(summary.addedFieldCount == 2)
        #expect(!Set([Self.filePrice, Self.fileStatus]).contains(defs[2].fieldID), "Added fields get fresh IDs")
    }

    @Test("An added status field is not made the catalogue's tab bar")
    func addedStatusFieldIsDemoted() async throws {
        let target = try makeTarget()
        _ = try await runImport(makeFile(), into: target)
        let built = try #require(try definitions(target).first { $0.name == "Built" })
        #expect(built.displayRole == DisplayRole.none)
    }

    @Test("Items already in the catalogue are skipped")
    func duplicatesSkipped() async throws {
        let target = try makeTarget()
        let summary = try await runImport(makeFile(), into: target)

        #expect(summary.skippedDuplicateCount == 1)
        #expect(summary.insertedItemIDs.count == 1)
        let items = try liveItems(target)
        #expect(items.count == 2)

        let hurricane = try #require(items.last)
        #expect(hurricane.notes == "Gift")
        #expect(hurricane.searchText.contains("hurricane"))
        let name = try #require(hurricane.fieldValues.first { $0.fieldType == .text })
        #expect(name.fieldDefinition?.fieldID == target.name.fieldID, "Values go into the matched field")
    }

    @Test("With skipping off, every item is added")
    func duplicatesKept() async throws {
        let target = try makeTarget()
        let summary = try await runImport(makeFile(), into: target, skippingDuplicates: false)
        #expect(summary.skippedDuplicateCount == 0)
        #expect(try liveItems(target).count == 3)
    }

    @Test("Option-list values the field lacks are added to its options")
    func missingOptionsAdded() async throws {
        let target = try makeTarget()
        let summary = try await runImport(makeFile(), into: target)
        let scale = try #require(try definitions(target).first { $0.name == "Scale" })
        #expect(scale.optionListOptions?.options == ["1:48", "1:72"])
        #expect(summary.addedOptionCount == 1)
    }

    @Test("Items already here get tiebreak keys covering the added fields")
    func existingItemsRefreshed() async throws {
        let target = try makeTarget()
        _ = try await runImport(makeFile(), into: target)

        let spitfire = try #require(try liveItems(target).first)
        let defs = try definitions(target)
        let value = try #require(spitfire.fieldValues.first)
        let expected = SortKeyEncoder.tiebreakKey(
            for: value, allFieldValuesOnItem: spitfire.fieldValues,
            fieldDefinitionsByPriority: defs, itemCreatedDate: spitfire.createdDate)
        #expect(value.tiebreakKey == expected)
    }

    @Test("Re-importing a catalogue's own export adds nothing")
    func ownExportIsAllDuplicates() async throws {
        let target = try makeTarget()
        let file = try await DataFileTestSupport.write(target.catalogue, in: target.container).decoded()
        let dto = try #require(file.catalogues.first)
        let summary = try await runImport(dto, into: target)

        #expect(summary.insertedItemIDs.isEmpty)
        #expect(summary.skippedDuplicateCount == 1)
        #expect(summary.addedFieldCount == 0)
        #expect(summary.addedOptionCount == 0)
    }

    @Test("Undo Import moves only the imported items to Recently Deleted")
    func undoImport() async throws {
        let target = try makeTarget()
        let summary = try await runImport(makeFile(), into: target, skippingDuplicates: false)
        let container = target.container
        let ids = summary.insertedItemIDs
        try await Task.detached {
            try await ItemTrashActor(modelContainer: container).setDeletedDate(.now, for: ids)
        }.value

        let items = try liveItems(target)
        #expect(items.count == 1)
        #expect(items.first?.createdDate == Self.existingDate)
    }
}
