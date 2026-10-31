//
//  FieldDefinitionDraftOptionEditTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Field Definition Draft Option Edit Tests

/// The pending rename/delete maps are what `AddEditCatalogueView` cascades to stored
/// FieldValues on save, so a wrong entry rewrites or drops real data.
@MainActor
struct FieldDefinitionDraftOptionEditTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    /// A saved option-list field, so edits are recorded for the cascade.
    private func savedDraft(options: [String], defaultValue: String? = nil) throws -> (FieldDefinitionDraft, ModelContainer) {
        let container = try makeContainer()
        let def = FieldDefinition(name: "Status", fieldType: .optionList)
        container.mainContext.insert(def)
        var draft = FieldDefinitionDraft(existingDefinition: def, name: "Status", fieldType: .optionList, priority: 0)
        draft.optionListOptions = OptionListOptions(options: options, defaultValue: defaultValue)
        return (draft, container)
    }

    @Test("Rename records original to new and swaps the option in place")
    func renameRecords() throws {
        var (draft, container) = try savedDraft(options: ["Owned", "Wanted"])
        withExtendedLifetime(container) {
            draft.renameOption("Owned", to: "Have")
            #expect(draft.optionListOptions.options == ["Have", "Wanted"])
            #expect(draft.pendingOptionRenames == ["Owned": "Have"])
        }
    }

    @Test("Chained renames collapse to original to latest")
    func chainCollapses() throws {
        var (draft, container) = try savedDraft(options: ["A"])
        withExtendedLifetime(container) {
            draft.renameOption("A", to: "B")
            draft.renameOption("B", to: "C")
            #expect(draft.pendingOptionRenames == ["A": "C"])
            #expect(draft.optionListOptions.options == ["C"])
        }
    }

    @Test("Deleting a renamed option records the original name and drops the rename")
    func deleteRenamedRecordsOriginal() throws {
        var (draft, container) = try savedDraft(options: ["A", "Z"])
        withExtendedLifetime(container) {
            draft.renameOption("A", to: "B")
            draft.deleteOption("B")
            #expect(draft.pendingOptionRenames.isEmpty)
            #expect(draft.pendingOptionDeletions == ["A"])
            #expect(draft.optionListOptions.options == ["Z"])
        }
    }

    @Test("Deleting an untouched option records its own name")
    func deleteRecordsName() throws {
        var (draft, container) = try savedDraft(options: ["A", "Z"])
        withExtendedLifetime(container) {
            draft.deleteOption("Z")
            #expect(draft.pendingOptionDeletions == ["Z"])
        }
    }

    @Test("The default follows a rename and clears on delete")
    func defaultFollowsRenameAndClears() throws {
        var (draft, container) = try savedDraft(options: ["Owned", "Wanted"], defaultValue: "Owned")
        withExtendedLifetime(container) {
            draft.renameOption("Owned", to: "Have")
            #expect(draft.optionListOptions.defaultValue == "Have")
            draft.deleteOption("Have")
            #expect(draft.optionListOptions.defaultValue == nil)
        }
    }

    @Test("Deleting another option leaves the default alone")
    func deleteKeepsOtherDefault() throws {
        var (draft, container) = try savedDraft(options: ["Owned", "Wanted"], defaultValue: "Owned")
        withExtendedLifetime(container) {
            draft.deleteOption("Wanted")
            #expect(draft.optionListOptions.defaultValue == "Owned")
        }
    }

    @Test("An unsaved field records no renames or deletions, but still edits its options")
    func unsavedRecordsNothing() {
        var draft = FieldDefinitionDraft(name: "Status", fieldType: .optionList, priority: 0)
        draft.optionListOptions = OptionListOptions(options: ["A", "B"], defaultValue: "A")
        draft.renameOption("A", to: "C")
        draft.deleteOption("B")
        #expect(draft.pendingOptionRenames.isEmpty)
        #expect(draft.pendingOptionDeletions.isEmpty)
        #expect(draft.optionListOptions.options == ["C"])
        #expect(draft.optionListOptions.defaultValue == "C")
    }
}
