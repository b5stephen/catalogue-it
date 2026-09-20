//
//  FieldDefinitionDraftEqualityTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Field Definition Draft Equality Tests

/// `hasSameContent(as:)` is what the catalogue and field editors use to decide whether a
/// swipe-down or tap outside the sheet would lose an edit. A comparison that misses a
/// property lets an edit be thrown away; one that includes SwiftUI identity locks every
/// sheet from the moment it opens.
@MainActor
struct FieldDefinitionDraftEqualityTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func draft(
        name: String = "Title",
        type: FieldType = .text,
        existing: FieldDefinition? = nil
    ) -> FieldDefinitionDraft {
        FieldDefinitionDraft(existingDefinition: existing, name: name, fieldType: type, priority: 0)
    }

    // MARK: - Identity

    @Test("Identical content with different SwiftUI ids compares equal")
    func identityIsIgnored() {
        let a = draft()
        let b = draft()
        #expect(a.id != b.id)
        #expect(a.hasSameContent(as: b))
    }

    @Test("Priority is ignored: the editor renumbers it on every drag")
    func priorityIsIgnored() {
        var a = draft()
        var b = draft()
        a.priority = 0
        b.priority = 7
        #expect(a.hasSameContent(as: b))
    }

    // MARK: - Each Property Counts

    @Test("Name difference is a change")
    func nameCounts() {
        #expect(!draft(name: "Title").hasSameContent(as: draft(name: "Name")))
    }

    @Test("Field type difference is a change")
    func fieldTypeCounts() {
        #expect(!draft(type: .text).hasSameContent(as: draft(type: .number)))
    }

    @Test("Display role difference is a change")
    func displayRoleCounts() {
        var a = draft(type: .boolean)
        var b = draft(type: .boolean)
        a.displayRole = .none
        b.displayRole = .flagFilter
        #expect(!a.hasSameContent(as: b))
    }

    @Test("Number options difference is a change")
    func numberOptionsCount() {
        var a = draft(type: .number)
        var b = draft(type: .number)
        a.numberOptions = NumberOptions(precision: 0)
        b.numberOptions = NumberOptions(precision: 2)
        #expect(!a.hasSameContent(as: b))
    }

    @Test("Option list difference is a change, including a reorder")
    func optionListOptionsCount() {
        var a = draft(type: .optionList)
        var b = draft(type: .optionList)
        a.optionListOptions = OptionListOptions(options: ["Owned", "Wanted"])
        b.optionListOptions = OptionListOptions(options: ["Wanted", "Owned"])
        #expect(!a.hasSameContent(as: b))
    }

    @Test("Boolean options difference is a change")
    func booleanOptionsCount() {
        var a = draft(type: .boolean)
        var b = draft(type: .boolean)
        a.booleanOptions.flagIconName = nil
        b.booleanOptions.flagIconName = "star"
        #expect(!a.hasSameContent(as: b))
    }

    @Test("A pending option rename is a change even though the options list looks the same")
    func pendingRenamesCount() {
        var a = draft(type: .optionList)
        var b = draft(type: .optionList)
        b.pendingOptionRenames = ["Owned": "Have"]
        #expect(!a.hasSameContent(as: b))
    }

    @Test("A pending option deletion is a change")
    func pendingDeletionsCount() {
        var a = draft(type: .optionList)
        var b = draft(type: .optionList)
        b.pendingOptionDeletions = ["Wanted"]
        #expect(!a.hasSameContent(as: b))
    }

    // MARK: - Existing Definition

    @Test("Same backing definition compares equal; nil against nil too")
    func existingDefinitionIdentity() throws {
        let container = try makeContainer()
        let def = FieldDefinition(name: "Title", fieldType: .text)
        container.mainContext.insert(def)

        #expect(draft(existing: def).hasSameContent(as: draft(existing: def)))
        #expect(draft(existing: nil).hasSameContent(as: draft(existing: nil)))
    }

    @Test("A different backing definition is a change even with identical fields")
    func existingDefinitionDiffers() throws {
        let container = try makeContainer()
        let first = FieldDefinition(name: "Title", fieldType: .text)
        let second = FieldDefinition(name: "Title", fieldType: .text)
        container.mainContext.insert(first)
        container.mainContext.insert(second)

        #expect(!draft(existing: first).hasSameContent(as: draft(existing: second)))
        #expect(!draft(existing: first).hasSameContent(as: draft(existing: nil)))
    }

    // MARK: - Arrays

    @Test("Element-wise comparison: same content in the same order is unchanged")
    func arraysWithSameContentAreEqual() {
        let a = [draft(name: "Title"), draft(name: "Year", type: .number)]
        let b = [draft(name: "Title"), draft(name: "Year", type: .number)]
        #expect(a.hasSameContent(as: b))
    }

    @Test("Reordering two fields is a change")
    func arrayReorderIsAChange() {
        let a = [draft(name: "Title"), draft(name: "Year", type: .number)]
        let b = [draft(name: "Year", type: .number), draft(name: "Title")]
        #expect(!a.hasSameContent(as: b))
    }

    @Test("Adding or removing a field is a change")
    func arrayLengthIsAChange() {
        let a = [draft(name: "Title")]
        let b = [draft(name: "Title"), draft(name: "Year", type: .number)]
        #expect(!a.hasSameContent(as: b))
        #expect(!b.hasSameContent(as: a))
        #expect([FieldDefinitionDraft]().hasSameContent(as: []))
    }
}
