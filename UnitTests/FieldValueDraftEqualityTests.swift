//
//  FieldValueDraftEqualityTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Field Value Draft Equality Tests

/// `hasSameValue(as:)` decides both whether `ItemSaveService` writes a draft back over a
/// value that may have changed on another device, and whether the item sheet lets a
/// swipe-down or tap outside discard it. Only the slot the field type uses may count.
@MainActor
struct FieldValueDraftEqualityTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func draft(_ type: FieldType, in container: ModelContainer) -> FieldValueDraft {
        let def = FieldDefinition(name: "Field", fieldType: type)
        container.mainContext.insert(def)
        return FieldValueDraft(fieldDefinition: def, fieldType: type)
    }

    @Test("Fresh drafts of the same type are unchanged")
    func freshDraftsMatch() throws {
        let c = try makeContainer()
        for type in FieldType.allCases {
            #expect(draft(type, in: c).hasSameValue(as: draft(type, in: c)))
        }
    }

    @Test("Text and option list compare the text slot")
    func textSlot() throws {
        let c = try makeContainer()
        for type in [FieldType.text, .optionList] {
            var a = draft(type, in: c)
            var b = draft(type, in: c)
            a.textValue = "Owned"
            b.textValue = "Owned"
            #expect(a.hasSameValue(as: b))
            b.textValue = "Wanted"
            #expect(!a.hasSameValue(as: b))
        }
    }

    @Test("Number compares the number slot, including nil against a value")
    func numberSlot() throws {
        let c = try makeContainer()
        var a = draft(.number, in: c)
        var b = draft(.number, in: c)
        a.numberValue = 1999
        b.numberValue = 1999
        #expect(a.hasSameValue(as: b))
        b.numberValue = nil
        #expect(!a.hasSameValue(as: b))
    }

    @Test("Date compares the date slot")
    func dateSlot() throws {
        let c = try makeContainer()
        let when = Date(timeIntervalSince1970: 1_000_000)
        var a = draft(.date, in: c)
        var b = draft(.date, in: c)
        a.dateValue = when
        b.dateValue = when
        #expect(a.hasSameValue(as: b))
        b.dateValue = when.addingTimeInterval(1)
        #expect(!a.hasSameValue(as: b))
    }

    @Test("Boolean compares the bool slot")
    func boolSlot() throws {
        let c = try makeContainer()
        var a = draft(.boolean, in: c)
        var b = draft(.boolean, in: c)
        a.boolValue = true
        b.boolValue = false
        #expect(!a.hasSameValue(as: b))
        b.boolValue = true
        #expect(a.hasSameValue(as: b))
    }

    @Test("A stray value in a slot the type doesn't use never reads as an edit")
    func unusedSlotsAreIgnored() throws {
        let c = try makeContainer()
        var a = draft(.text, in: c)
        var b = draft(.text, in: c)
        a.textValue = "Same"
        b.textValue = "Same"
        b.numberValue = 42
        b.dateValue = .now
        b.boolValue = true
        #expect(a.hasSameValue(as: b))
    }

    @Test("Different field types never match, whatever the values")
    func differentTypesNeverMatch() throws {
        let c = try makeContainer()
        let a = draft(.text, in: c)
        let b = draft(.number, in: c)
        #expect(!a.hasSameValue(as: b))
    }
}
