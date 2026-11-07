//
//  SpreadsheetExportTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Spreadsheet Export Tests

@MainActor
struct SpreadsheetExportTests {

    // MARK: - Fixtures

    @MainActor private struct Fixture {
        let container: ModelContainer
        let catalogue: Catalogue
        let name: FieldDefinition
        let year: FieldDefinition
        let added: FieldDefinition
        let owned: FieldDefinition
        var context: ModelContext { container.mainContext }
    }

    /// Fields are inserted out of priority order: Name, Year, Added (date), Owned (Yes/No).
    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Planes", iconName: "airplane", colorHex: "#FF0000")
        ctx.insert(catalogue)

        func field(_ name: String, _ type: FieldType, _ priority: Int) -> FieldDefinition {
            let definition = FieldDefinition(name: name, fieldType: type, priority: priority)
            definition.catalogue = catalogue
            ctx.insert(definition)
            return definition
        }
        let owned = field("Owned", .boolean, 3)
        let added = field("Acquired", .date, 2)
        let year = field("Year", .number, 1)
        let name = field("Name", .text, 0)
        return Fixture(container: container, catalogue: catalogue, name: name, year: year, added: added, owned: owned)
    }

    @discardableResult
    private func addItem(
        _ f: Fixture,
        name: String? = nil,
        year: Double? = nil,
        acquired: Date? = nil,
        owned: Bool? = nil,
        notes: String? = nil,
        created: Date = .now
    ) -> CatalogueItem {
        let item = CatalogueItem(notes: notes)
        item.createdDate = created
        item.catalogue = f.catalogue
        f.context.insert(item)

        func value(_ definition: FieldDefinition, _ set: (FieldValue) -> Void) {
            let fv = FieldValue(fieldDefinition: definition, fieldType: definition.fieldType)
            set(fv)
            fv.item = item
            f.context.insert(fv)
        }
        if let name { value(f.name) { $0.textValue = name } }
        if let year { value(f.year) { $0.numberValue = year } }
        if let acquired { value(f.added) { $0.dateValue = acquired } }
        if let owned { value(f.owned) { $0.boolValue = owned } }
        return item
    }

    private func allColumns(_ f: Fixture) -> [ExportColumn] {
        ExportFormat.spreadsheet.columns(for: f.catalogue)
    }

    private func request(
        _ f: Fixture,
        items: [CatalogueItem],
        columns: [ExportColumn]? = nil,
        options: SpreadsheetEncoding.Options = .init(),
        filtered: Bool = false
    ) throws -> SpreadsheetRequest {
        // Identifiers are temporary until saved, and meaningless to the writer's context.
        try f.context.save()
        return SpreadsheetRequest(
            catalogueID: f.catalogue.persistentModelID,
            itemIDs: items.map(\.persistentModelID),
            columns: columns ?? allColumns(f),
            options: options,
            filtered: filtered
        )
    }

    /// Entered the way the app does: a plain `Task` would run the writer on the main thread.
    private func csv(_ request: SpreadsheetRequest, in f: Fixture) async throws -> String {
        let container = f.container
        let url = try await Task.detached {
            try await SpreadsheetWriter(modelContainer: container).writeCSV(request)
        }.value
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private func tsv(_ request: SpreadsheetRequest, in f: Fixture) async throws -> String {
        let container = f.container
        return try await Task.detached {
            try await SpreadsheetWriter(modelContainer: container).tsv(request)
        }.value
    }

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\r\n").dropLast().map { $0 }
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Cell Encoding

    @Test("CSV quotes cells containing a comma, quote, CR or LF, and doubles inner quotes")
    func csvQuoting() {
        #expect(SpreadsheetEncoding.csvCell("plain") == "plain")
        #expect(SpreadsheetEncoding.csvCell("a,b") == "\"a,b\"")
        #expect(SpreadsheetEncoding.csvCell(#"say "hi""#) == #""say ""hi""""#)
        #expect(SpreadsheetEncoding.csvCell("one\ntwo") == "\"one\ntwo\"")
        #expect(SpreadsheetEncoding.csvCell("one\rtwo") == "\"one\rtwo\"")
        #expect(SpreadsheetEncoding.csvCell("one\r\ntwo") == "\"one\r\ntwo\"")
        #expect(SpreadsheetEncoding.csvCell("") == "")
    }

    @Test("A CSV row ends in CRLF and a TSV row in LF")
    func rowTerminators() {
        #expect(SpreadsheetEncoding.row(["a", "b,c"], as: .csv) == "a,\"b,c\"\r\n")
        #expect(SpreadsheetEncoding.row(["a", "b"], as: .tsv) == "a\tb\n")
    }

    @Test("TSV replaces tabs and line breaks inside a cell with spaces")
    func tsvEscaping() {
        #expect(SpreadsheetEncoding.tsvCell("a\tb") == "a b")
        #expect(SpreadsheetEncoding.tsvCell("a\nb") == "a b")
        #expect(SpreadsheetEncoding.tsvCell("a\r\nb") == "a b")
        #expect(SpreadsheetEncoding.tsvCell("a\rb") == "a b")
        #expect(SpreadsheetEncoding.tsvCell("a,\"b\"") == "a,\"b\"", "Commas and quotes need no escaping in a TSV")
    }

    @Test("Numbers are plain: no grouping, no trailing .0, a . decimal, any sign")
    func plainNumbers() {
        #expect(SpreadsheetEncoding.plainNumber(1_234_567) == "1234567")
        #expect(SpreadsheetEncoding.plainNumber(1936) == "1936")
        #expect(SpreadsheetEncoding.plainNumber(12.5) == "12.5")
        #expect(SpreadsheetEncoding.plainNumber(0.1) == "0.1")
        #expect(SpreadsheetEncoding.plainNumber(1234.5678) == "1234.5678")
        #expect(SpreadsheetEncoding.plainNumber(-42) == "-42")
        #expect(SpreadsheetEncoding.plainNumber(-0.25) == "-0.25")
        #expect(SpreadsheetEncoding.plainNumber(0) == "0")
        #expect(SpreadsheetEncoding.plainNumber(-0.0) == "0")
        #expect(SpreadsheetEncoding.plainNumber(0.00001) == "0.00001")
        #expect(SpreadsheetEncoding.plainNumber(1e20) == "100000000000000000000")
        #expect(SpreadsheetEncoding.plainNumber(.nan) == "")
    }

    @Test("Dates are the ISO calendar day in the given time zone")
    func isoDates() throws {
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let honolulu = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        let instant = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC
        #expect(SpreadsheetEncoding.isoDate(instant, timeZone: auckland) == "2023-11-15")
        #expect(SpreadsheetEncoding.isoDate(instant, timeZone: honolulu) == "2023-11-14")
        #expect(SpreadsheetEncoding.isoDate(day(2024, 2, 9)) == "2024-02-09")
    }

    @Test("File name is the catalogue's, with Filtered when set, and no path separators")
    func fileNames() {
        #expect(SpreadsheetEncoding.fileName(catalogueName: "Planes", filtered: false) == "Planes.csv")
        #expect(SpreadsheetEncoding.fileName(catalogueName: "Planes", filtered: true) == "Planes – Filtered.csv")
        #expect(SpreadsheetEncoding.fileName(catalogueName: "A/B: C", filtered: false) == "A-B- C.csv")
    }

    // MARK: - Writer

    @Test("The file starts with a byte order mark and uses CRLF line endings")
    func bomAndCRLF() async throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire")
        let text = try await csv(try request(f, items: [item]), in: f)

        #expect(text.hasPrefix("\u{FEFF}Name,Year,Acquired,Owned,Notes,Date Added,Photo Count\r\n"))
        #expect(text.hasSuffix("\r\n"))
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "Every line break is CRLF")
        #expect(text.utf8.starts(with: [0xEF, 0xBB, 0xBF]))
    }

    @Test("For spreadsheets: ISO date, plain number, Yes/No labels, notes as stored")
    func spreadsheetValues() async throws {
        let f = try makeFixture()
        let created = day(2025, 3, 7)
        let item = addItem(f, name: "Spitfire", year: 1_936, acquired: day(2024, 12, 25), owned: true,
                           notes: "Mk I, early", created: created)
        let text = try await csv(try request(f, items: [item]), in: f)

        #expect(lines(text)[1] == "Spitfire,1936,2024-12-25,Yes,\"Mk I, early\",2025-03-07,0")
    }

    @Test("A missing Yes/No value reads as the No label, and a custom label is used")
    func yesNoLabels() async throws {
        let f = try makeFixture()
        f.owned.fieldOptions = .boolean(BooleanOptions(trueLabel: "Got it", falseLabel: "Want it"))
        let present = addItem(f, name: "A", owned: true)
        let off = addItem(f, name: "B", owned: false)
        let missing = addItem(f, name: "C") // predates the field: no FieldValue at all
        let text = try await csv(try request(f, items: [present, off, missing], columns: [.field(f.owned.fieldID)]), in: f)

        #expect(lines(text) == ["\u{FEFF}Owned", "Got it", "Want it", "Want it"])
    }

    @Test("Columns follow field priority however the request lists them")
    func columnOrder() async throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire", year: 1936)
        let shuffled: [ExportColumn] = [.photoCount, .field(f.owned.fieldID), .field(f.name.fieldID), .notes,
                                        .field(f.year.fieldID)]
        let text = try await csv(try request(f, items: [item], columns: shuffled), in: f)

        #expect(lines(text)[0] == "\u{FEFF}Name,Year,Owned,Notes,Photo Count")
    }

    @Test("A column whose field no longer exists is dropped")
    func staleColumn() async throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire", year: 1936)
        let columns = allColumns(f) + [.field(UUID())]
        let text = try await csv(try request(f, items: [item], columns: columns), in: f)

        #expect(lines(text)[0] == "\u{FEFF}Name,Year,Acquired,Owned,Notes,Date Added,Photo Count")
        #expect(lines(text)[1].split(separator: ",", omittingEmptySubsequences: false).count == 7)
    }

    @Test("Unticked columns are left out")
    func unticked() async throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire", year: 1936)
        let text = try await csv(try request(f, items: [item], columns: [.field(f.name.fieldID), .photoCount]), in: f)

        #expect(lines(text) == ["\u{FEFF}Name,Photo Count", "Spitfire,0"])
    }

    @Test("The header row is optional")
    func headerOnOff() async throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire")
        let columns: [ExportColumn] = [.field(f.name.fieldID)]

        let with = try await csv(try request(f, items: [item], columns: columns), in: f)
        #expect(lines(with) == ["\u{FEFF}Name", "Spitfire"])

        var options = SpreadsheetEncoding.Options()
        options.includesHeader = false
        let without = try await csv(try request(f, items: [item], columns: columns, options: options), in: f)
        #expect(lines(without) == ["\u{FEFF}Spitfire"])
    }

    @Test("Rows come out in the caller's order, across batches, skipping deleted items")
    func callerOrder() async throws {
        let f = try makeFixture()
        let items = (0..<450).map { addItem(f, name: "Item \($0)", created: Date(timeIntervalSince1970: Double($0))) }
        let order = Array(items.reversed())
        try f.context.save()

        var options = SpreadsheetEncoding.Options()
        options.includesHeader = false
        let columns: [ExportColumn] = [.field(f.name.fieldID)]
        let text = try await csv(try request(f, items: order, columns: columns, options: options), in: f)
        #expect(lines(text).map { $0.replacingOccurrences(of: "\u{FEFF}", with: "") } == order.map { $0.fieldValues[0].textValue! })
    }

    @Test("Photo count comes from a count query")
    func photoCount() async throws {
        let f = try makeFixture()
        let two = addItem(f, name: "Two")
        let none = addItem(f, name: "None")
        for index in 0..<2 {
            let photo = ItemPhoto(imageData: Data([0xFF, 0xD8]), priority: index)
            photo.item = two
            f.context.insert(photo)
        }
        try f.context.save()

        let text = try await csv(try request(f, items: [two, none], columns: [.field(f.name.fieldID), .photoCount]), in: f)
        #expect(lines(text) == ["\u{FEFF}Name,Photo Count", "Two,2", "None,0"])
    }

    @Test("As shown in app matches displayValue(for:) for every field")
    func asShown() async throws {
        let f = try makeFixture()
        f.year.fieldOptions = .number(NumberOptions(format: .currency, precision: 2, usesGroupingSeparator: true))
        let item = addItem(f, name: "Spitfire", year: 1_234_567, acquired: day(2024, 12, 25), owned: true)
        var options = SpreadsheetEncoding.Options()
        options.valueStyle = .asShown
        options.includesHeader = false
        let columns = [f.name, f.year, f.added, f.owned].map { ExportColumn.field($0.fieldID) }
        try f.context.save()

        let text = try await csv(try request(f, items: [item], columns: columns, options: options), in: f)
        let expected = [f.name, f.year, f.added, f.owned].map { SpreadsheetEncoding.csvCell(item.displayValue(for: $0)) }
        #expect(lines(text) == ["\u{FEFF}" + expected.joined(separator: ",")])
        #expect(text.contains(FieldValueFormatter.date(day(2024, 12, 25))))
    }

    @Test("Copy writes tab-separated rows without a byte order mark")
    func tsvOutput() async throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire", year: 1936, notes: "line one\nline two\tand more")
        let columns: [ExportColumn] = [.field(f.name.fieldID), .field(f.year.fieldID), .notes]
        let text = try await tsv(try request(f, items: [item], columns: columns), in: f)

        #expect(text == "Name\tYear\tNotes\nSpitfire\t1936\tline one line two and more\n")
    }

    @Test("The written file is named for the catalogue, or Filtered")
    func writtenFileName() async throws {
        let f = try makeFixture()
        let item = addItem(f, name: "Spitfire")
        let container = f.container
        for (filtered, expected) in [(false, "Planes.csv"), (true, "Planes – Filtered.csv")] {
            let request = try request(f, items: [item], filtered: filtered)
            let url = try await Task.detached {
                try await SpreadsheetWriter(modelContainer: container).writeCSV(request)
            }.value
            #expect(url.lastPathComponent == expected)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }
}
