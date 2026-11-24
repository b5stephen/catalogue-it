//
//  XLSXReaderTests.swift
//  UnitTests
//

import Compression
import Foundation
import Testing
@testable import catalogue_it

struct XLSXReaderTests {

    // MARK: Workbooks

    @Test("Cells read as the values Excel shows, placed by their references")
    func readsCells() throws {
        let sheets = try ExcelReader.read(workbook())
        #expect(sheets.map(\.name) == ["Planes", "Notes"], "Hidden and empty sheets are left out")

        let rows = sheets[0].table.rows
        #expect(rows.count == 3, "The row with only a styled blank cell is dropped")
        #expect(rows[0] == ["Name", "Built", "Price", "Share", "Flies", "Notes", "", "Weight"])
        #expect(rows[1] == ["Spitfire Mk I", "2023-03-15", "€12.50", "25", "TRUE", "Line\none", "", "3.00"])
        #expect(rows[2] == ["Hurricane", "", "€-3.00", "", "", "", "", ""])
        #expect(sheets[1].table.rows == [["Remember"]])
    }

    @Test("A table read from a workbook goes through the column planner like a CSV")
    func plansColumns() throws {
        let table = try ExcelReader.read(workbook())[0].table
        let parser = ImportValueParser(locale: Locale(identifier: "de_DE"), timeZone: TimeZone(identifier: "Europe/Berlin")!)
        #expect(TableImportPlanner.guessHasHeaderRow(table, parser: parser))
        #expect(TableImportPlanner.inferType(of: ["2023-03-15", "2024-01-02"], parser: parser) == .date)
        #expect(parser.number("€12.50")?.value == 12.5, "Written locale-free, so a comma-decimal locale still reads it")
    }

    @Test("1904-based workbooks count days from 1904")
    func dates1904() throws {
        let data = workbook(date1904: true, sheet: #"<row r="1"><c r="A1" s="1"><v>1</v></c></row>"#, notes: "")
        #expect(try ExcelReader.read(data)[0].table.rows == [["1904-01-02"]])
    }

    @Test("Serials around Excel's phantom 29 February 1900")
    func leapYearBug() {
        let formatter = ExcelReader.CellFormatter(styles: [], uses1904Dates: false)
        #expect(formatter.day(serial: 1) == "1900-01-01")
        #expect(formatter.day(serial: 59) == "1900-02-28")
        #expect(formatter.day(serial: 61) == "1900-03-01")
        #expect(formatter.day(serial: 45_000.75) == "2023-03-15", "The time of day is dropped")
        #expect(formatter.day(serial: 0) == nil)
    }

    // MARK: Formats

    @Test("Format codes are classified by their first section")
    func formatCodes() {
        typealias Style = ExcelReader.CellFormatter.Style
        #expect(Style(code: "General") == .general)
        #expect(Style(code: "@") == .general)
        #expect(Style(code: "#,##0.00") == .number(fractionDigits: 2, currencySymbol: nil, isPercent: false))
        #expect(Style(code: "0.0%") == .number(fractionDigits: 1, currencySymbol: nil, isPercent: true))
        #expect(Style(code: "[$€-407]#,##0.00;[Red]-#,##0.00") == .number(fractionDigits: 2, currencySymbol: "€", isPercent: false))
        #expect(Style(code: "[$-409]#,##0") == .number(fractionDigits: 0, currencySymbol: nil, isPercent: false))
        #expect(Style(code: #"_-* #,##0.00\ "€"_-"#) == .number(fractionDigits: 2, currencySymbol: "€", isPercent: false))
        #expect(Style(code: ##""$"#,##0"##) == .number(fractionDigits: 0, currencySymbol: "$", isPercent: false))
        #expect(Style(code: "d mmm yyyy") == .date)
        #expect(Style(code: "[$-409]mmmm d, yyyy;@") == .date)
        #expect(Style(code: #"0 "days""#) == .general, "Quoted text isn't a date")
        #expect(Style(code: "h:mm AM/PM") == .time(showsSeconds: false, isElapsed: false))
        #expect(Style(code: "[h]:mm:ss") == .time(showsSeconds: true, isElapsed: true))
    }

    @Test("Numbers are plain, rounded to 15 significant digits, with the format's decimals")
    func plainNumbers() {
        typealias Formatter = ExcelReader.CellFormatter
        #expect(Formatter.plain(0.1 + 0.2, fractionDigits: 0) == "0.3")
        #expect(Formatter.plain(1e20, fractionDigits: 0) == "100000000000000000000")
        #expect(Formatter.plain(1.5e-7, fractionDigits: 0) == "0.00000015")
        #expect(Formatter.plain(9_780_306_406_157, fractionDigits: 0) == "9780306406157")
        #expect(Formatter.plain(12.5, fractionDigits: 2) == "12.50")
        #expect(Formatter.plain(7, fractionDigits: 1) == "7.0")
        #expect(Formatter.plain(-2.25, fractionDigits: 1) == "-2.25")
    }

    @Test("Times are written as a clock, elapsed hours unwrapped")
    func times() {
        let formatter = ExcelReader.CellFormatter(
            styles: [.time(showsSeconds: false, isElapsed: false), .time(showsSeconds: true, isElapsed: true)],
            uses1904Dates: false)
        #expect(formatter.text(for: 0.604166666666667, style: 0) == "14:30")
        #expect(formatter.text(for: 1.5, style: 1) == "36:00:00")
    }

    @Test("Escaped control characters are restored")
    func unescape() {
        #expect(XLSXReader.unescape("a_x000D__x000A_b") == "a\r\nb")
        #expect(XLSXReader.unescape("snake_x_case") == "snake_x_case")
    }

    // MARK: Other Files

    @Test("Files that aren't readable workbooks say what to do instead")
    func unreadable() throws {
        var compound = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        compound.append(Data(count: 504))
        #expect(throws: ExcelReader.ReadError.notAWorkbook) { try ExcelReader.read(compound) }

        let numbers = zip(["Index/Document.iwa": Data([1, 2, 3])])
        #expect(throws: ExcelReader.ReadError.numbersFile) { try ExcelReader.read(numbers) }

        let other = zip(["readme.txt": Data("hello".utf8)])
        #expect(throws: ExcelReader.ReadError.notAWorkbook) { try ExcelReader.read(other) }

        #expect(throws: ExcelReader.ReadError.notAWorkbook) { try ExcelReader.read(Data([0x50, 0x4B, 0x03, 0x04, 0, 0])) }

        let empty = workbook(sheet: #"<row r="1"><c r="A1" s="1"/></row>"#, notes: "")
        #expect(throws: DelimitedTextParser.ParseError.empty) { try ExcelReader.read(empty) }
    }

    @Test("Zip entries can be stored or deflated")
    func zipEntries() throws {
        let text = Data(String(repeating: "catalogue ", count: 500).utf8)
        let archive = try ZipArchive(zip(["a.txt": text, "b.txt": Data("short".utf8)], deflating: ["a.txt"]))
        #expect(try archive.contents(of: "a.txt") == text)
        #expect(try archive.contents(of: "/b.txt") == Data("short".utf8))
        #expect(try archive.contents(of: "missing") == nil)
    }

    // MARK: Fixtures

    /// Sheets: Planes (`sheet`), Hidden, Empty, then Notes (`notes`).
    private func workbook(date1904: Bool = false, sheet: String? = nil, notes: String = "Remember") -> Data {
        let main = sheet ?? """
            <row r="1">
              <c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c>
              <c r="D1" t="s"><v>3</v></c><c r="E1" t="s"><v>4</v></c><c r="F1" t="s"><v>5</v></c>
              <c r="H1" t="s"><v>6</v></c>
            </row>
            <row r="2">
              <c r="A2" t="s"><v>7</v></c><c r="B2" s="1"><v>45000</v></c><c r="C2" s="2"><v>12.5</v></c>
              <c r="D2" s="3"><v>0.25</v></c><c r="E2" t="b"><v>1</v></c>
              <c r="F2" t="inlineStr"><is><t>Line_x000A_one</t></is></c><c r="H2" s="4"><v>3</v></c>
            </row>
            <row r="3"><c r="A3" s="1"/></row>
            <row r="5">
              <c r="A5" t="str"><f>"Hurri"&amp;"cane"</f><v>Hurricane</v></c>
              <c r="B5" t="e"><v>#N/A</v></c><c r="C5" s="2"><v>-3</v></c>
            </row>
            """
        let ns = #"xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships""#
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        func worksheet(_ rows: String) -> Data {
            Data(#"<?xml version="1.0" encoding="UTF-8"?><worksheet \#(ns)><sheetData>\#(rows)</sheetData></worksheet>"#.utf8)
        }
        let strings = ["Name", "Built", "Price", "Share", "Flies", "Notes", "Weight"]
            .map { "<si><t>\($0)</t></si>" }.joined()
            + #"<si><r><t>Spitfire</t></r><r><rPr><b/></rPr><t xml:space="preserve"> Mk I</t></r><rPh><t>スピットファイア</t></rPh></si>"#

        return zip([
            "_rels/.rels": Data("""
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                <Relationship Id="rId1" Type="\(rel)/officeDocument" Target="xl/workbook.xml"/>
                </Relationships>
                """.utf8),
            "xl/workbook.xml": Data("""
                <workbook \(ns)><workbookPr\(date1904 ? #" date1904="1""# : "")/><sheets>
                <sheet name="Planes" sheetId="1" r:id="rId1"/>
                <sheet name="Hidden" sheetId="2" state="hidden" r:id="rId2"/>
                <sheet name="Empty" sheetId="3" r:id="rId3"/>
                <sheet name="Notes" sheetId="4" r:id="rId4"/>
                </sheets></workbook>
                """.utf8),
            "xl/_rels/workbook.xml.rels": Data("""
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                <Relationship Id="rId1" Type="\(rel)/worksheet" Target="worksheets/sheet1.xml"/>
                <Relationship Id="rId2" Type="\(rel)/worksheet" Target="worksheets/sheet2.xml"/>
                <Relationship Id="rId3" Type="\(rel)/worksheet" Target="/xl/worksheets/sheet3.xml"/>
                <Relationship Id="rId4" Type="\(rel)/worksheet" Target="./worksheets/../worksheets/sheet4.xml"/>
                <Relationship Id="rId5" Type="\(rel)/sharedStrings" Target="sharedStrings.xml"/>
                <Relationship Id="rId6" Type="\(rel)/styles" Target="styles.xml"/>
                </Relationships>
                """.utf8),
            "xl/sharedStrings.xml": Data("<sst \(ns)>\(strings)</sst>".utf8),
            "xl/styles.xml": Data(#"""
                <styleSheet \#(ns)>
                <numFmts count="1"><numFmt numFmtId="164" formatCode="[$€-407]#,##0.00;[Red]-#,##0.00"/></numFmts>
                <cellStyleXfs count="1"><xf numFmtId="14"/></cellStyleXfs>
                <cellXfs count="5"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/><xf numFmtId="9"/><xf numFmtId="2"/></cellXfs>
                </styleSheet>
                """#.utf8),
            "xl/worksheets/sheet1.xml": worksheet(main),
            "xl/worksheets/sheet2.xml": worksheet(#"<row r="1"><c r="A1" t="inlineStr"><is><t>Secret</t></is></c></row>"#),
            "xl/worksheets/sheet3.xml": worksheet(""),
            "xl/worksheets/sheet4.xml": worksheet(notes.isEmpty ? "" : #"<row r="1"><c r="A1" t="inlineStr"><is><t>\#(notes)</t></is></c></row>"#),
        ], deflating: ["xl/worksheets/sheet1.xml", "xl/sharedStrings.xml"])
    }

    /// A minimal zip: no CRCs, which the reader doesn't check.
    private func zip(_ files: [String: Data], deflating: Set<String> = []) -> Data {
        var archive = Data()
        var directory = Data()
        func append16(_ value: Int, to data: inout Data) { data.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]) }
        func append32(_ value: Int, to data: inout Data) { append16(value & 0xFFFF, to: &data); append16(value >> 16, to: &data) }

        for (name, contents) in files.sorted(by: { $0.key < $1.key }) {
            let isDeflated = deflating.contains(name)
            let stored = isDeflated ? deflate(contents) : contents
            let nameData = Data(name.utf8)
            let offset = archive.count
            for isCentral in [false, true] {
                var header = Data()
                append32(isCentral ? 0x0201_4B50 : 0x0403_4B50, to: &header)
                if isCentral { append16(20, to: &header) }
                append16(20, to: &header)
                append16(0, to: &header)
                append16(isDeflated ? 8 : 0, to: &header)
                append32(0, to: &header)
                append32(0, to: &header)
                append32(stored.count, to: &header)
                append32(contents.count, to: &header)
                append16(nameData.count, to: &header)
                append16(0, to: &header)
                if isCentral {
                    for _ in 0..<3 { append16(0, to: &header) }
                    append32(0, to: &header)
                    append32(offset, to: &header)
                    directory.append(header + nameData)
                } else {
                    archive.append(header + nameData + stored)
                }
            }
        }
        let directoryOffset = archive.count
        archive.append(directory)
        append32(0x0605_4B50, to: &archive)
        append16(0, to: &archive)
        append16(0, to: &archive)
        append16(files.count, to: &archive)
        append16(files.count, to: &archive)
        append32(directory.count, to: &archive)
        append32(directoryOffset, to: &archive)
        append16(0, to: &archive)
        return archive
    }

    private func deflate(_ data: Data) -> Data {
        var output = Data(count: data.count + 1_024)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return output.prefix(written)
    }
}
