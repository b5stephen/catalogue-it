//
//  FieldOptionsPersistenceTests.swift
//  UnitTests
//

import Testing
import CoreData
import Foundation
import SwiftData
@testable import catalogue_it

/// `FieldDefinition.fieldOptions` and `Catalogue.layoutOptions` are Codable composites that
/// SwiftData flattens into columns. Two things have wiped them silently:
///
/// - `ModelContext.fetchHistory` (Sept 2026, the one that reached users): one call leaves the
///   container writing every composite of a dirty row as NULL from the second save on. History
///   is now read through `PersistentHistoryReader` instead;
///   `compositesSurviveSavesAfterACoreDataHistoryFetch` is the regression test and
///   `fetchHistoryStillWipesComposites` pins the bug as a known issue.
/// - A stored Codable type that is not `nonisolated`: under the project's main-actor default
///   isolation its conformance is invisible from off the main actor, where SwiftData may
///   encode. `storedCodableTypesConformOffTheMainActor` checks the conformance itself, since
///   the test host encodes where an isolated conformance happens to be visible.
///
/// `fieldOptionsSurviveASaveAndReopen` stays as the end-to-end check of the real save path.
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

    // MARK: - History fetches

    /// The coordinator behind a container, captured the way `RemoteChangeObserver` gets it:
    /// from the `NSPersistentStoreRemoteChange` notification a local save posts.
    private func coordinator(observedDuring save: () throws -> Void) throws -> NSPersistentStoreCoordinator {
        final class Box: @unchecked Sendable { var coordinator: NSPersistentStoreCoordinator? }
        let box = Box()
        let observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil
        ) { box.coordinator = $0.object as? NSPersistentStoreCoordinator }
        defer { NotificationCenter.default.removeObserver(observer) }
        try save()
        let deadline = Date.now.addingTimeInterval(5)
        while box.coordinator == nil, Date.now < deadline {
            RunLoop.main.run(until: Date.now.addingTimeInterval(0.05))
        }
        return try #require(box.coordinator, "the store never posted NSPersistentStoreRemoteChange")
    }

    /// Two fields whose options get edited across three saves, with the history read the
    /// remote-change pass makes between them. Every option must still be there at the end.
    private func editOptionsAcrossSaves(
        in context: ModelContext,
        readingHistory: (ModelContext) throws -> Void
    ) throws -> (status: FieldDefinition, owned: FieldDefinition) {
        let catalogue = Catalogue(name: "Films")
        context.insert(catalogue)
        let status = FieldDefinition(name: "Status", fieldType: .optionList, priority: 0)
        let owned = FieldDefinition(name: "Owned", fieldType: .boolean, priority: 1)
        for field in [status, owned] { context.insert(field); field.catalogue = catalogue }
        status.optionListOptions = OptionListOptions(options: ["Alpha"])
        try context.save()
        try readingHistory(context)

        owned.booleanOptions = BooleanOptions(flagIconName: "heart.fill")
        try context.save()
        try readingHistory(context)

        // A save that assigns nothing composite on `owned` still rewrites its composite.
        status.optionListOptions = OptionListOptions(options: ["Alpha", "Beta"])
        owned.priority = 1
        try context.save()
        return (status, owned)
    }

    /// The regression this file exists for (Sept 2026): the remote-change pass reads history
    /// after every save, and doing that through `ModelContext.fetchHistory` left every
    /// composite column NULL from the second save on. The Core Data reader must not.
    @Test @MainActor func compositesSurviveSavesAfterACoreDataHistoryFetch() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        let container = try openContainer(at: url)
        let context = container.mainContext
        context.author = "main"

        let coordinator = try coordinator {
            context.insert(Catalogue(name: "Warm-up"))
            try context.save()
        }
        let fields = try editOptionsAcrossSaves(in: context) { _ in
            _ = try PersistentHistoryReader.mergedFieldContent(
                coordinator: coordinator, since: .date(.distantPast), excludingAuthor: "main")
        }
        #expect(fields.status.optionListOptions?.options == ["Alpha", "Beta"])
        #expect(fields.owned.booleanOptions?.flagIconName == "heart.fill")

        let reopened = try openContainer(at: url)
        let stored = try reopened.mainContext.fetch(FetchDescriptor<FieldDefinition>(sortBy: [SortDescriptor(\.priority)]))
        #expect(stored.map(\.fieldOptions) == [
            .optionList(OptionListOptions(options: ["Alpha", "Beta"])),
            .boolean(BooleanOptions(flagIconName: "heart.fill")),
        ])
    }

    /// The SwiftData bug itself, kept as a known issue so the day it stops reproducing is
    /// noticed: one `ModelContext.fetchHistory` call — result unused — and the composite
    /// written by the second save after it is NULL. Until then, `fetchHistory` stays banned
    /// (see `PersistentHistoryReader`).
    @Test @MainActor func fetchHistoryStillWipesComposites() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        let container = try openContainer(at: url)
        let fields = try editOptionsAcrossSaves(in: container.mainContext) { context in
            _ = try context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        }
        withKnownIssue("ModelContext.fetchHistory breaks composite encoding (iOS 26.5, 27.0)") {
            #expect(fields.status.optionListOptions?.options == ["Alpha", "Beta"])
        }
    }

    /// The reader reports the item behind a merged value, and only for content written by
    /// another author: the main context's own saves and derived-only rewrites start nothing.
    @Test @MainActor func historyReaderReportsItemsWithMergedFieldContent() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        let container = try openContainer(at: url)
        let main = container.mainContext
        main.author = "main"

        let catalogue = Catalogue(name: "Films")
        let field = FieldDefinition(name: "Title", fieldType: .text)
        let item = CatalogueItem()
        main.insert(catalogue); main.insert(field); main.insert(item)
        field.catalogue = catalogue
        item.catalogue = catalogue
        let value = FieldValue(fieldDefinition: field, fieldType: .text)
        value.item = item
        main.insert(value)
        let coordinator = try coordinator { try main.save() }

        // Written by "main": ignored.
        var merged = try PersistentHistoryReader.mergedFieldContent(
            coordinator: coordinator, since: .date(.distantPast), excludingAuthor: "main")
        #expect(merged.itemCreatedDates.isEmpty)
        let token = try #require(merged.newestToken)

        // Another author (a sync merge, in the app) edits the value's content.
        let other = ModelContext(container)
        other.author = "mirroring"
        let valueID = value.persistentModelID
        let otherValue = try #require(other.model(for: valueID) as? FieldValue)
        otherValue.textValue = "Alien"
        try other.save()

        merged = try PersistentHistoryReader.mergedFieldContent(
            coordinator: coordinator, since: .token(token), excludingAuthor: "main")
        #expect(merged.itemCreatedDates == [item.createdDate])
        let afterEdit = try #require(merged.newestToken)

        // The same author rewriting only derived columns: ignored.
        otherValue.sortKey = "alien"
        try other.save()
        merged = try PersistentHistoryReader.mergedFieldContent(
            coordinator: coordinator, since: .token(afterEdit), excludingAuthor: "main")
        #expect(merged.itemCreatedDates.isEmpty)
    }
}
