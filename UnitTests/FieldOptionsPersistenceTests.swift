//
//  FieldOptionsPersistenceTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

/// `FieldDefinition.fieldOptions` is a Codable composite that SwiftData encodes off the main
/// actor. Under the project's main-actor default isolation, a stored Codable type that is not
/// `nonisolated` has an isolated conformance, which that executor cannot see — and the column
/// is silently saved as NULL.
///
/// `storedCodableTypesConformOffTheMainActor` is the one that catches a regression: the test
/// host happens to encode on an executor where the isolated conformance is visible, so the
/// save-and-reopen test passed even while the app was wiping the column. It stays as the
/// end-to-end check of the real SwiftData path.
@Suite(.serialized)
struct FieldOptionsPersistenceTests {

    private func makeStoreURL() -> URL {
        URL.temporaryDirectory.appending(path: "field-options-\(UUID().uuidString).store")
    }

    private func removeStore(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path + suffix))
        }
    }

    private func openContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: CatalogueSchemaCurrent.self),
            migrationPlan: CatalogueMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
    }

    private static let sampleOptions: [FieldOptions] = [
        .number(NumberOptions(format: .currency, precision: 2)),
        .optionList(OptionListOptions(options: ["Mint", "Used"], defaultValue: "Mint")),
        .boolean(BooleanOptions(trueLabel: "Owned", falseLabel: "Wanted", defaultValue: false, flagIconName: "star", flagColorHex: "#FF0000")),
    ]

    /// The failure mode itself: the conformance lookup SwiftData relies on, made from a
    /// context that is not the main actor.
    @Test func storedCodableTypesConformOffTheMainActor() async {
        let results: [String: Bool] = await Task.detached {
            var results: [String: Bool] = [:]
            for value in [
                ("FieldOptions", FieldOptions.boolean(BooleanOptions()) as Any),
                ("OptionListOptions", OptionListOptions() as Any),
                ("NumberOptions", NumberOptions() as Any),
                ("BooleanOptions", BooleanOptions() as Any),
                ("FieldType", FieldType.text as Any),
                ("NumberFormat", NumberFormat.currency as Any),
                ("DisplayRole", DisplayRole.none as Any),
                ("CatalogueLayoutOptions", CatalogueLayoutOptions() as Any),
            ] {
                results[value.0] = (value.1 as? any Encodable) != nil && (type(of: value.1) as? any Decodable.Type) != nil
            }
            return results
        }.value

        for (name, conforms) in results.sorted(by: { $0.key < $1.key }) {
            #expect(conforms, "\(name) must be `nonisolated` — its Codable conformance is invisible off the main actor")
        }
    }

    /// The symptom: options written by one container must be there when a fresh container
    /// opens the same file — through the real SwiftData save path, not JSONEncoder.
    @Test @MainActor func fieldOptionsSurviveASaveAndReopen() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        do {
            let container = try openContainer(at: url)
            let context = container.mainContext
            let catalogue = Catalogue(name: "Films")
            context.insert(catalogue)
            for (index, options) in Self.sampleOptions.enumerated() {
                let fieldType: FieldType = switch options {
                case .number: .number
                case .optionList: .optionList
                case .boolean: .boolean
                }
                let field = FieldDefinition(name: "Field \(index)", fieldType: fieldType, priority: index)
                context.insert(field)
                field.catalogue = catalogue
                field.fieldOptions = options
            }
            try context.save()

            // The in-memory object is the first casualty: a failed encode leaves it nil.
            for field in catalogue.sortedFieldDefinitions {
                #expect(field.fieldOptions != nil, "\(field.name) lost its options on save")
            }
        }

        let reopened = try openContainer(at: url)
        let fields = try reopened.mainContext.fetch(FetchDescriptor<FieldDefinition>(sortBy: [SortDescriptor(\.priority)]))
        #expect(fields.count == Self.sampleOptions.count)
        for (field, expected) in zip(fields, Self.sampleOptions) {
            #expect(field.fieldOptions == expected, "\(field.name) came back as \(String(describing: field.fieldOptions))")
        }
    }
}
