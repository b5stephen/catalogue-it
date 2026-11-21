//
//  TableImportPlannerTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

struct TableImportPlannerTests {

    private func parser() -> ImportValueParser {
        ImportValueParser(locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "Europe/London")!)
    }

    private func table(_ text: String) throws -> ImportTable {
        try DelimitedTextParser.parse(text)
    }

    private func plan(_ table: ImportTable, _ targets: [ColumnTarget], hasHeaderRow: Bool = true) -> TableImportPlanner.Plan {
        TableImportPlanner.Plan(hasHeaderRow: hasHeaderRow, targets: targets, catalogueName: "Planes", colorHex: "#007AFF")
    }

    // MARK: Guessing

    @Test("Column types are guessed from every value")
    func inference() {
        let p = parser()
        #expect(TableImportPlanner.inferType(of: ["12", "1,200.5", "£3"], parser: p) == .number)
        #expect(TableImportPlanner.inferType(of: ["007", "12"], parser: p) == .text, "A leading zero is a code")
        #expect(TableImportPlanner.inferType(of: ["2026-01-01", "3 Mar 2026"], parser: p) == .date)
        #expect(TableImportPlanner.inferType(of: ["x", "", "yes"].filter { !$0.isEmpty }, parser: p) == .boolean)
        #expect(TableImportPlanner.inferType(of: ["1", "0", "1"], parser: p) == .number)
        #expect(TableImportPlanner.inferType(of: Array(repeating: ["1:48", "1:72"], count: 5).flatMap { $0 }, parser: p) == .optionList)
        #expect(TableImportPlanner.inferType(of: ["Spitfire", "Hurricane", "Lancaster"], parser: p) == .text)
        #expect(TableImportPlanner.inferType(of: ["1:48", "1:72", "1:48", "1:72", "1:32"], parser: p) == .text, "More than half distinct")
        #expect(TableImportPlanner.inferType(of: ["12", "n/a", "3"], parser: p) == .number, "Placeholders don't count")
    }

    @Test("A header row is recognised, and a sheet of data isn't taken for one")
    func headerGuess() throws {
        #expect(TableImportPlanner.guessHasHeaderRow(try table("Name,Year\nSpitfire,1938\nHurricane,1937\n"), parser: parser()))
        #expect(!TableImportPlanner.guessHasHeaderRow(try table("Spitfire,1938\nHurricane,1937\n"), parser: parser()))
    }

    @Test("A day above 12 settles the date order")
    func impliedOrder() throws {
        #expect(TableImportPlanner.impliedDateOrder(try table("Built\n1/2/2020\n25/2/2020\n"), hasHeaderRow: true, parser: parser()) == .dayMonthYear)
        #expect(TableImportPlanner.impliedDateOrder(try table("Built\n2/25/2020\n"), hasHeaderRow: true, parser: parser()) == .monthDayYear)
        #expect(TableImportPlanner.impliedDateOrder(try table("Built\n1/2/2020\n"), hasHeaderRow: true, parser: parser()) == nil)
    }

    @Test("The app's own export headings and existing field names are matched")
    func defaultTargets() throws {
        let t = try table("Name,Scale,Notes,Date Added,Photo Count,Cost\nSpitfire,1:48,ok,2026-01-01,2,12\n")
        let nameID = UUID()
        let columns = TableImportPlanner.summarise(t, hasHeaderRow: true, parser: parser())
        let targets = TableImportPlanner.defaultTargets(
            for: columns, existing: [TargetField(fieldID: nameID, name: "name", fieldType: .text)])
        #expect(targets == [.field(nameID), .newField(.text), .notes, .dateAdded, .skip, .newField(.number)])
    }

    // MARK: Checking

    @Test("Values the target can't read are counted, with examples")
    func check() throws {
        let t = try table("Price\n12\nn/a\n£3\nabout 4\nsoon\n")
        let check = TableImportPlanner.check(t, column: 0, target: .newField(.number), hasHeaderRow: true, existing: [], parser: parser())
        #expect(check.unreadableCount == 2, "n/a is a placeholder, left empty without a warning")
        #expect(check.examples == ["about 4", "soon"])
    }

    @Test("Values an existing option list lacks are listed, ignoring case")
    func newOptions() throws {
        let id = UUID()
        let scale = TargetField(fieldID: id, name: "Scale", fieldType: .optionList, options: ["1:48"])
        let check = TableImportPlanner.check(try table("Scale\n1:48\n1:72\n1:72\n"), column: 0, target: .field(id),
                                             hasHeaderRow: true, existing: [scale], parser: parser())
        #expect(check.newOptions == ["1:72"])
        #expect(check.unreadableCount == 0)
    }

    // MARK: Building

    @Test("New fields take the headers, unique, with options from the values")
    func newFields() throws {
        let t = try table("Name,Name,Scale,Price\nSpitfire,A,1:48,£12.50\nHurricane,B,1:72,£8\nLancaster,C,1:48,£30.125\n")
        let built = TableImportPlanner.build(
            t, plan: plan(t, [.newField(.text), .newField(.text), .newField(.optionList), .newField(.number)]),
            existing: [], parser: parser())
        let fields = built.catalogue.fieldDefinitions
        #expect(fields.map(\.name) == ["Name", "Name 2", "Scale", "Price"])
        #expect(fields[2].fieldOptions == .optionList(OptionListOptions(options: ["1:48", "1:72"])))
        #expect(fields[3].fieldOptions == .number(NumberOptions(format: .currency, precision: 3)))
        #expect(built.catalogue.items.count == 3)
    }

    @Test("Rows keep the sheet's order as Date Added, unless a column gives it")
    func createdDates() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let t = try table("Name\nA\nB\nC\n")
        let built = TableImportPlanner.build(t, plan: plan(t, [.newField(.text)]), existing: [], parser: parser(), start: start)
        #expect(built.catalogue.items.map(\.createdDate) == [start, start + 0.001, start + 0.002])

        let dated = try table("Name,Added\nA,2020-05-01\n")
        let item = try #require(TableImportPlanner.build(dated, plan: plan(dated, [.newField(.text), .dateAdded]),
                                                          existing: [], parser: parser()).catalogue.items.first)
        #expect(item.createdDate == parser().date("2020-05-01"))
    }

    @Test("Rows with nothing in an imported column are skipped")
    func emptyRows() throws {
        let t = try table("Name,Ignored\nA,x\n,y\n")
        let built = TableImportPlanner.build(t, plan: plan(t, [.newField(.text), .skip]), existing: [], parser: parser())
        #expect(built.catalogue.items.count == 1)
        #expect(built.skippedRowCount == 1)
    }

    @Test("An existing option is used in its own spelling")
    func canonicalOption() throws {
        let id = UUID()
        let status = TargetField(fieldID: id, name: "Status", fieldType: .optionList, options: ["Owned", "Wishlist"])
        let t = try table("Status\nowned\nWISHLIST\n")
        let built = TableImportPlanner.build(t, plan: plan(t, [.field(id)]), existing: [status], parser: parser())
        #expect(built.catalogue.items.flatMap(\.fieldValues).map(\.textValue) == ["Owned", "Wishlist"])
    }
}

// MARK: - Duplicates

struct TableImportDuplicateTests {

    private func parser() -> ImportValueParser {
        ImportValueParser(locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "Europe/London")!)
    }

    @Test("Text keys ignore case and accents; number keys compare by value")
    func keys() {
        let p = parser()
        #expect(TableImportPlanner.duplicateKey(" Spitfire ", fieldType: .text, parser: p) == TableImportPlanner.duplicateKey("spitfire", fieldType: .text, parser: p))
        #expect(TableImportPlanner.duplicateKey("Café", fieldType: .optionList, parser: p) == "cafe")
        #expect(TableImportPlanner.duplicateKey("1,200", fieldType: .number, parser: p) == "1200")
        #expect(TableImportPlanner.duplicateKey("1200.0", fieldType: .number, parser: p) == "1200")
        #expect(TableImportPlanner.duplicateKey("", fieldType: .text, parser: p) == nil)
        #expect(TableImportPlanner.duplicateKey("2026-01-01", fieldType: .date, parser: p) == nil)
    }

    @Test("Rows matching an existing key are left out and counted")
    func skipsMatchingRows() throws {
        let id = UUID()
        let name = TargetField(fieldID: id, name: "Name", fieldType: .text)
        let table = try DelimitedTextParser.parse("Name,Scale\nSPITFIRE,1:48\nTempest,1:48\nHurricane,1:72\n")
        let check = TableImportPlanner.DuplicateCheck(column: 0, fieldType: .text, existingKeys: ["spitfire", "hurricane"])
        #expect(TableImportPlanner.duplicateRowCount(table, hasHeaderRow: true, check: check, parser: parser()) == 2)

        let built = TableImportPlanner.build(
            table,
            plan: .init(hasHeaderRow: true, targets: [.field(id), .newField(.text)], catalogueName: "", colorHex: "",
                        duplicateCheck: check),
            existing: [name], parser: parser())
        #expect(built.catalogue.items.count == 1)
        #expect(built.duplicateRowCount == 2)
        #expect(built.catalogue.items.first?.fieldValues.first?.textValue == "Tempest")
    }

    @Test("Only text and number fields can identify duplicates")
    func eligibleTypes() {
        #expect(FieldType.allCases.filter(TableImportPlanner.canMatchDuplicates) == [.text, .number])
    }

    @Test("Changing the key column's field clears the check")
    @MainActor
    func retargetClearsCheck() throws {
        let id = UUID()
        let other = UUID()
        let table = try DelimitedTextParser.parse("Name,Code\nSpitfire,A1\n")
        let model = TableImportModel(table: table, sourceName: "x")
        model.setDestination(.newCatalogue, fields: [
            TargetField(fieldID: id, name: "Name", fieldType: .text),
            TargetField(fieldID: other, name: "Code", fieldType: .text),
        ])
        model.setDuplicateCheck(column: 0, existingKeys: ["spitfire"])
        #expect(model.duplicateRowCount == 1)
        model.setTarget(.newField(.text), forColumn: 0)
        #expect(model.duplicateCheck == nil)
        #expect(model.duplicateRowCount == 0)
    }
}

// MARK: - Round Trip

/// A catalogue exported by the Spreadsheet format and imported back reproduces its values.
@MainActor
struct SpreadsheetRoundTripTests {

    private struct Fixture {
        let container: ModelContainer
        let catalogue: Catalogue
        let fields: [FieldDefinition]
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Planes")
        ctx.insert(catalogue)
        func field(_ name: String, _ type: FieldType, _ priority: Int) -> FieldDefinition {
            let definition = FieldDefinition(name: name, fieldType: type, priority: priority)
            ctx.insert(definition)
            definition.catalogue = catalogue
            return definition
        }
        let name = field("Name", .text, 0)
        let year = field("Year", .number, 1)
        let built = field("Built", .boolean, 2)
        built.booleanOptions = BooleanOptions(trueLabel: "Built", falseLabel: "Unbuilt")
        let acquired = field("Acquired", .date, 3)
        let scale = field("Scale", .optionList, 4)
        scale.optionListOptions = OptionListOptions(options: ["1:48", "1:72"])

        let rows: [(String, Double, Bool, Int, String, String?)] = [
            ("Spitfire, Mk IX", 1938.5, true, 1, "1:48", "Decals \"missing\""),
            ("Hurricane", -12, false, 15, "1:72", nil),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        for (index, row) in rows.enumerated() {
            let item = CatalogueItem(notes: row.5)
            ctx.insert(item)
            item.catalogue = catalogue
            item.createdDate = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400)
            func value(_ definition: FieldDefinition, _ set: (FieldValue) -> Void) {
                let value = FieldValue(fieldDefinition: nil, fieldType: definition.fieldType)
                ctx.insert(value)
                value.fieldDefinition = definition
                value.item = item
                set(value)
            }
            value(name) { $0.textValue = row.0 }
            value(year) { $0.numberValue = row.1 }
            value(built) { $0.boolValue = row.2 }
            value(acquired) { $0.dateValue = calendar.date(from: DateComponents(year: 2025, month: 6, day: row.3, hour: 9)) }
            value(scale) { $0.textValue = row.4 }
        }
        try ctx.save()
        return Fixture(container: container, catalogue: catalogue, fields: [name, year, built, acquired, scale])
    }

    private func exportCSV(_ f: Fixture) async throws -> Data {
        let items = f.catalogue.items.sorted { $0.createdDate < $1.createdDate }
        let request = SpreadsheetRequest(
            catalogueID: f.catalogue.persistentModelID,
            itemIDs: items.map(\.persistentModelID),
            columns: ExportFormat.spreadsheet.columns(for: f.catalogue))
        let container = f.container
        let url = try await Task.detached {
            try await SpreadsheetWriter(modelContainer: container).writeCSV(request)
        }.value
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return try Data(contentsOf: url)
    }

    private func describe(_ items: [CatalogueItem], fields: [FieldDefinition]) -> [[String]] {
        let calendar = Calendar.autoupdatingCurrent
        return items.sorted { $0.createdDate < $1.createdDate }.map { item in
            fields.map { field in
                let value = item.fieldValues.first { $0.fieldDefinition?.name == field.name }
                switch field.fieldType {
                case .text, .optionList: return value?.textValue ?? ""
                case .number: return value?.numberValue.map { "\($0)" } ?? ""
                case .boolean: return "\(value?.boolValue ?? false)"
                case .date:
                    return value?.dateValue.map { "\(calendar.dateComponents([.year, .month, .day], from: $0))" } ?? ""
                }
            } + [item.notes ?? "", "\(calendar.startOfDay(for: item.createdDate))"]
        }
    }

    @Test("Exported as a spreadsheet, a catalogue imports back as a new one with the same values")
    func roundTripAsNewCatalogue() async throws {
        let f = try makeFixture()
        let table = try DelimitedTextParser.parse(try await exportCSV(f))
        let parser = ImportValueParser()
        #expect(TableImportPlanner.guessHasHeaderRow(table, parser: parser))

        let columns = TableImportPlanner.summarise(table, hasHeaderRow: true, parser: parser)
        let targets = TableImportPlanner.defaultTargets(for: columns, existing: [])
        #expect(targets == [.newField(.text), .newField(.number), .newField(.text), .newField(.date),
                            .newField(.text), .notes, .dateAdded, .skip],
                "Two items are too few for an option list, and Built's labels aren't Yes/No words")

        // As the user would set them in the mapping sheet.
        var chosen = targets
        chosen[2] = .newField(.boolean)
        chosen[4] = .newField(.optionList)
        let built = TableImportPlanner.build(
            table,
            plan: .init(hasHeaderRow: true, targets: chosen, catalogueName: "Copy", colorHex: "#000000"),
            existing: [], parser: parser)
        let container = f.container
        let file = CatalogueExportFile(exportedAt: .now, catalogues: [built.catalogue])
        let summary = try await Task.detached {
            try await ItemImporter(modelContainer: container).importAsNewCatalogues(file, priorityOffset: 1)
        }.value

        let copy = try #require(summary.catalogueIDs.first.flatMap { f.container.mainContext.model(for: $0) as? Catalogue })
        // "Built"/"Unbuilt" aren't Yes/No words for a new field, so only the default reading of
        // the new field differs: compare everything else.
        var expected = describe(f.catalogue.items, fields: f.fields)
        var actual = describe(copy.items, fields: copy.sortedFieldDefinitions)
        for index in expected.indices {
            expected[index].remove(at: 2)
            actual[index].remove(at: 2)
        }
        #expect(actual == expected)
    }

    @Test("Imported back into its own catalogue, every column matches its field and reads its labels")
    func roundTripIntoOwnCatalogue() async throws {
        let f = try makeFixture()
        let table = try DelimitedTextParser.parse(try await exportCSV(f))
        let parser = ImportValueParser()
        let existing = f.catalogue.sortedFieldDefinitions.map(TargetField.init)
        let columns = TableImportPlanner.summarise(table, hasHeaderRow: true, parser: parser)
        let targets = TableImportPlanner.defaultTargets(for: columns, existing: existing)
        #expect(targets == f.fields.map { .field($0.fieldID) } + [.notes, .dateAdded, .skip])
        for index in targets.indices {
            let check = TableImportPlanner.check(table, column: index, target: targets[index], hasHeaderRow: true,
                                                 existing: existing, parser: parser)
            #expect(check.unreadableCount == 0, "Column \(columns[index].header)")
        }

        let built = TableImportPlanner.build(
            table, plan: .init(hasHeaderRow: true, targets: targets, catalogueName: "", colorHex: ""),
            existing: existing, parser: parser)
        let container = f.container
        let catalogueID = f.catalogue.persistentModelID
        let dto = built.catalogue
        let summary = try await Task.detached {
            try await ItemImporter(modelContainer: container)
                .importCatalogue(dto, into: catalogueID, skippingDuplicates: false, matchingFieldsByName: false)
        }.value
        #expect(summary.addedFieldCount == 0)
        #expect(summary.insertedItemIDs.count == 2)

        let imported = summary.insertedItemIDs.compactMap { f.container.mainContext.model(for: $0) as? CatalogueItem }
        let originals = f.catalogue.items.filter { !summary.insertedItemIDs.contains($0.persistentModelID) }
        #expect(describe(imported, fields: f.fields) == describe(originals, fields: f.fields))
    }
}
