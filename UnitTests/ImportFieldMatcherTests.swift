//
//  ImportFieldMatcherTests.swift
//  UnitTests
//

import Testing
import Foundation
@testable import catalogue_it

struct ImportFieldMatcherTests {

    private func fileField(_ name: String, _ type: FieldType, priority: Int, id: UUID = UUID()) -> FieldDefinitionDTO {
        FieldDefinitionDTO(fieldID: id, name: name, fieldType: type, priority: priority, fieldOptions: nil, displayRole: nil)
    }

    @Test("A field from this catalogue matches by ID, even after a rename")
    func matchesByID() {
        let id = UUID()
        let existing = [ImportFieldMatcher.ExistingField(fieldID: id, name: "Maker", fieldType: .text)]
        let entries = ImportFieldMatcher.match([fileField("Manufacturer", .text, priority: 0, id: id)], to: existing)
        #expect(entries.map(\.match) == [.existing(fieldID: id, name: "Maker")])
    }

    @Test("Names match ignoring case, accents and surrounding space")
    func matchesByName() {
        let id = UUID()
        let existing = [ImportFieldMatcher.ExistingField(fieldID: id, name: "Catégorie", fieldType: .optionList)]
        let entries = ImportFieldMatcher.match([fileField(" categorie ", .optionList, priority: 0)], to: existing)
        #expect(entries.map(\.match) == [.existing(fieldID: id, name: "Catégorie")])
    }

    @Test("A name match of another type becomes a new field with a unique name")
    func typeMismatchAddsField() {
        let existing = [
            ImportFieldMatcher.ExistingField(fieldID: UUID(), name: "Year", fieldType: .text),
            ImportFieldMatcher.ExistingField(fieldID: UUID(), name: "Year 2", fieldType: .date),
        ]
        let entries = ImportFieldMatcher.match([fileField("Year", .number, priority: 0)], to: existing)
        #expect(entries.map(\.match) == [.new(name: "Year 3")])
    }

    @Test("Each existing field takes one file field; the rest are added with distinct names")
    func existingFieldClaimedOnce() {
        let id = UUID()
        let existing = [ImportFieldMatcher.ExistingField(fieldID: id, name: "Name", fieldType: .text)]
        let entries = ImportFieldMatcher.match([
            fileField("Name", .text, priority: 0),
            fileField("name", .text, priority: 1),
            fileField("NAME", .text, priority: 2),
        ], to: existing)
        #expect(entries.map(\.match) == [
            .existing(fieldID: id, name: "Name"),
            .new(name: "name 2"),
            .new(name: "NAME 3"),
        ])
    }

    @Test("Entries follow the file's field order")
    func ordersByPriority() {
        let entries = ImportFieldMatcher.match([
            fileField("Second", .text, priority: 1),
            fileField("First", .text, priority: 0),
        ], to: [])
        #expect(entries.map(\.name) == ["First", "Second"])
    }
}
