//
//  ItemShareTextTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Item Share Text Tests

@MainActor
struct ItemShareTextTests {

    private struct Fixture {
        let container: ModelContainer
        let catalogue: Catalogue
        let name: FieldDefinition
        let year: FieldDefinition
        let owned: FieldDefinition
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let catalogue = Catalogue(name: "Planes")
        context.insert(catalogue)
        let name = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        let year = FieldDefinition(name: "Year", fieldType: .text, priority: 1)
        let owned = FieldDefinition(name: "Owned", fieldType: .boolean, priority: 2)
        for definition in [name, year, owned] {
            context.insert(definition)
            definition.catalogue = catalogue
        }
        return Fixture(container: container, catalogue: catalogue, name: name, year: year, owned: owned)
    }

    @discardableResult
    private func addItem(
        _ f: Fixture,
        name: String? = nil,
        year: String? = nil,
        owned: Bool? = nil,
        notes: String? = nil
    ) -> CatalogueItem {
        let context = f.container.mainContext
        let item = CatalogueItem(notes: notes)
        context.insert(item)
        item.catalogue = f.catalogue
        func add(_ definition: FieldDefinition, _ configure: (FieldValue) -> Void) {
            let value = FieldValue(fieldDefinition: definition, fieldType: definition.fieldType)
            context.insert(value)
            value.item = item
            configure(value)
        }
        if let name { add(f.name) { $0.textValue = name } }
        if let year { add(f.year) { $0.textValue = year } }
        if let owned { add(f.owned) { $0.boolValue = owned } }
        return item
    }

    private func allColumns(_ f: Fixture) -> Set<ExportColumn> {
        Set(ExportFormat.message.columns(for: f.catalogue))
    }

    // MARK: - Single item

    @Test("Single item: title line, then Field: value lines")
    func singleItemWithLabels() throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire", year: "1938", owned: true, notes: "Boxed")
        let text = ItemShareText.text(for: [item], in: f.catalogue, columns: allColumns(f))
        #expect(text == "Spitfire\nYear: 1938\nOwned: Yes\nNotes: Boxed")
    }

    @Test("Without field names the values share one line")
    func singleItemWithoutLabels() throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire", year: "1938", owned: true)
        var options = ItemShareText.Options()
        options.showFieldNames = false
        let text = ItemShareText.text(for: [item], in: f.catalogue, columns: allColumns(f), options: options)
        #expect(text == "Spitfire\n1938 · Yes")
    }

    @Test("Blanks and No are left out by default, kept as a dash or the No label when off")
    func blanksAndNo() throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire", owned: false)
        let columns = allColumns(f)
        #expect(ItemShareText.text(for: [item], in: f.catalogue, columns: columns) == "Spitfire")

        var options = ItemShareText.Options()
        options.leaveOutBlanks = false
        let text = ItemShareText.text(for: [item], in: f.catalogue, columns: columns, options: options)
        #expect(text == "Spitfire\nYear: –\nOwned: No\nNotes: –")
    }

    @Test("A Yes/No field with no FieldValue reads as No")
    func missingYesNoValueIsNo() throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire")
        let columns: Set<ExportColumn> = [.field(f.owned.fieldID)]
        #expect(ItemShareText.text(for: [item], in: f.catalogue, columns: columns) == "Spitfire")

        var options = ItemShareText.Options()
        options.leaveOutBlanks = false
        #expect(ItemShareText.text(for: [item], in: f.catalogue, columns: columns, options: options) == "Spitfire\nOwned: No")
    }

    @Test("Only ticked columns appear, and Notes only when ticked")
    func tickedColumnsOnly() throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire", year: "1938", notes: "Boxed")
        let year: Set<ExportColumn> = [.field(f.year.fieldID)]
        #expect(ItemShareText.text(for: [item], in: f.catalogue, columns: year) == "Spitfire\nYear: 1938")
        let notes: Set<ExportColumn> = [.notes]
        #expect(ItemShareText.text(for: [item], in: f.catalogue, columns: notes) == "Spitfire\nNotes: Boxed")
    }

    @Test("An item with no title value is Untitled Item")
    func titleFallback() throws {
        let f = try makeFixture()
        let item = addItem(f, year: "1938")
        #expect(ItemShareText.title(for: item, in: f.catalogue) == "Untitled Item")
        #expect(ItemShareText.text(for: [item], in: f.catalogue, columns: allColumns(f)) == "Untitled Item\nYear: 1938")
    }

    @Test("Duplicate FieldValues resolve through value(for:), matching the displayed value")
    func duplicateFieldValues() throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire", year: "1938")
        let context = f.container.mainContext
        let duplicate = FieldValue(fieldDefinition: f.year, fieldType: .text)
        context.insert(duplicate)
        duplicate.item = item
        duplicate.textValue = "1940"

        let expected = item.displayValue(for: f.year)
        let text = ItemShareText.text(for: [item], in: f.catalogue, columns: [.field(f.year.fieldID)])
        #expect(text == "Spitfire\nYear: \(expected)")
    }

    // MARK: - Several items

    @Test("Several items: header with count, then a bullet per item")
    func listFormat() throws {
        let f = try makeFixture()
        let a = addItem(f, name: "Spitfire", year: "1938", owned: true)
        let b = addItem(f, name: "Hurricane")
        let text = ItemShareText.text(for: [a, b], in: f.catalogue, columns: allColumns(f))
        let lines = text.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Planes · "))
        #expect(lines[0].contains("2"))
        #expect(lines[1] == "• Spitfire — 1938, Yes")
        #expect(lines[2] == "• Hurricane", "No dash when an item has no values")
    }

    @Test("List format keeps notes on one line")
    func listNotesCollapse() throws {
        let f = try makeFixture()
        let a = addItem(f, name: "Spitfire", notes: "Line one\nLine two")
        let b = addItem(f, name: "Hurricane")
        let text = ItemShareText.text(for: [a, b], in: f.catalogue, columns: [.notes])
        #expect(text.contains("• Spitfire — Line one Line two"))
    }

    @Test("No items yields no text")
    func noItems() throws {
        let f = try makeFixture()
        #expect(ItemShareText.text(for: [], in: f.catalogue, columns: allColumns(f)).isEmpty)
    }
}
