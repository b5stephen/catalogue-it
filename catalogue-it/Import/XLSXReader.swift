//
//  XLSXReader.swift
//  catalogue-it
//

import Foundation

// MARK: - XLSX Reader

/// Office Open XML workbooks (.xlsx): a zip of XML parts.
nonisolated enum XLSXReader {

    /// Visible worksheets with at least one value, in workbook order.
    static func sheets(_ data: Data) throws -> [ExcelReader.Sheet] {
        try Workbook(ZipArchive(data)).sheets()
    }

    // MARK: Workbook

    private struct Workbook {
        let archive: ZipArchive

        init(_ archive: ZipArchive) {
            self.archive = archive
        }

        func sheets() throws -> [ExcelReader.Sheet] {
            if archive.paths.contains("Index/Document.iwa") { throw ExcelReader.ReadError.numbersFile }
            let packageRelationships = try relationships(of: "")
            let workbookPath = packageRelationships.values.first { $0.type.hasSuffix("/officeDocument") }?.target ?? "xl/workbook.xml"
            guard let workbookData = try archive.contents(of: workbookPath) else { throw ExcelReader.ReadError.notAWorkbook }

            let workbook = try parse(workbookData, with: WorkbookParser())
            let related = try relationships(of: workbookPath)
            let sharedStrings = try related.values.first { $0.type.hasSuffix("/sharedStrings") }
                .flatMap { try archive.contents(of: $0.target) }
                .map { try parse($0, with: SharedStringsParser()).strings } ?? []
            let styles = try related.values.first { $0.type.hasSuffix("/styles") }
                .flatMap { try archive.contents(of: $0.target) }
                .map { try parse($0, with: StylesParser()) }
            let formatter = ExcelReader.CellFormatter(
                styles: styles?.cellFormats.map { ExcelReader.CellFormatter.Style(code: styles?.formatCode(for: $0) ?? "General") } ?? [],
                uses1904Dates: workbook.uses1904Dates)

            var result: [ExcelReader.Sheet] = []
            for entry in workbook.sheets where entry.isVisible {
                guard let relationship = related[entry.relationshipID], relationship.type.hasSuffix("/worksheet"),
                      let sheetData = try archive.contents(of: relationship.target) else { continue }
                let parser = SheetParser(sharedStrings: sharedStrings, formatter: formatter)
                if let table = try parse(sheetData, with: parser).table() {
                    result.append(ExcelReader.Sheet(name: entry.name, table: table))
                }
            }
            return result
        }

        /// The relationships of the part at `path` (the package itself when empty), by id,
        /// with targets resolved to archive paths.
        private func relationships(of path: String) throws -> [String: Relationship] {
            let directory = (path as NSString).deletingLastPathComponent
            let relsPath = (directory as NSString).appendingPathComponent("_rels/\((path as NSString).lastPathComponent).rels")
            guard let data = try archive.contents(of: relsPath) else { return [:] }
            var result: [String: Relationship] = [:]
            for relationship in try parse(data, with: RelationshipsParser()).relationships {
                result[relationship.id] = Relationship(
                    id: relationship.id, type: relationship.type,
                    target: Self.resolve(relationship.target, from: directory))
            }
            return result
        }

        static func resolve(_ target: String, from directory: String) -> String {
            let joined = target.hasPrefix("/") ? String(target.dropFirst()) : (directory as NSString).appendingPathComponent(target)
            var parts: [Substring] = []
            for part in joined.split(separator: "/") {
                switch part {
                case ".": continue
                case "..": _ = parts.popLast()
                default: parts.append(part)
                }
            }
            return parts.joined(separator: "/")
        }

        private func parse<P: XMLParserDelegate>(_ data: Data, with delegate: P) throws -> P {
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = delegate
            guard parser.parse() else { throw ExcelReader.ReadError.notAWorkbook }
            return delegate
        }
    }

    struct Relationship {
        let id: String
        let type: String
        let target: String
    }

    /// OOXML writes control characters as `_xHHHH_`.
    static func unescape(_ text: String) -> String {
        guard text.contains("_x") else { return text }
        var result = ""
        var rest = Substring(text)
        while let range = rest.range(of: "_x") {
            result += rest[..<range.lowerBound]
            let hex = rest[range.upperBound...].prefix(5)
            if hex.count == 5, hex.last == "_", let code = UInt32(hex.dropLast(), radix: 16), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
                rest = rest[rest.index(range.upperBound, offsetBy: 5)...]
            } else {
                result += "_x"
                rest = rest[range.upperBound...]
            }
        }
        return result + rest
    }
}

// MARK: - XML Parsers

private extension Dictionary where Key == String, Value == String {
    /// An attribute by local name: namespace processing leaves attribute prefixes in place.
    nonisolated func attribute(_ name: String) -> String? {
        self[name] ?? first { $0.key.hasSuffix(":" + name) }?.value
    }
}

private nonisolated final class RelationshipsParser: NSObject, XMLParserDelegate {
    private(set) var relationships: [XLSXReader.Relationship] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard elementName == "Relationship", attributes["TargetMode"] != "External",
              let id = attributes["Id"], let type = attributes["Type"], let target = attributes["Target"] else { return }
        relationships.append(XLSXReader.Relationship(id: id, type: type, target: target))
    }
}

private nonisolated final class WorkbookParser: NSObject, XMLParserDelegate {
    struct Entry {
        let name: String
        let relationshipID: String
        let isVisible: Bool
    }

    private(set) var sheets: [Entry] = []
    private(set) var uses1904Dates = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "workbookPr":
            uses1904Dates = ["1", "true"].contains(attributes["date1904"])
        case "sheet":
            guard let name = attributes["name"], let id = attributes.attribute("id") else { return }
            sheets.append(Entry(name: name, relationshipID: id, isVisible: (attributes["state"] ?? "visible") == "visible"))
        default:
            break
        }
    }
}

private nonisolated final class SharedStringsParser: NSObject, XMLParserDelegate {
    private(set) var strings: [String] = []
    private var current = ""
    private var inText = false
    /// Phonetic guides (`rPh`) hold readings, not the string.
    private var phoneticDepth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "si": current = ""
        case "rPh": phoneticDepth += 1
        case "t": inText = phoneticDepth == 0
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "si": strings.append(XLSXReader.unescape(current))
        case "rPh": phoneticDepth -= 1
        case "t": inText = false
        default: break
        }
    }
}

private nonisolated final class StylesParser: NSObject, XMLParserDelegate {
    private(set) var cellFormats: [Int] = []
    private var customCodes: [Int: String] = [:]
    private var inCellFormats = false

    func formatCode(for id: Int) -> String {
        customCodes[id] ?? ExcelReader.builtInFormatCode(id)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "numFmt":
            if let id = attributes["numFmtId"].flatMap(Int.init), let code = attributes["formatCode"] { customCodes[id] = code }
        case "cellXfs":
            inCellFormats = true
        case "xf" where inCellFormats:
            // Not `cellStyleXfs`: a cell's `s` indexes `cellXfs`.
            cellFormats.append(attributes["numFmtId"].flatMap(Int.init) ?? 0)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "cellXfs" { inCellFormats = false }
    }
}

private nonisolated final class SheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let formatter: ExcelReader.CellFormatter
    private var rows: [[Int: String]] = []
    private var row: [Int: String] = [:]
    private var column = -1
    private var cellType: String?
    private var cellStyle: Int?
    private var value = ""
    private var inline = ""
    private var capturing: Capture?
    private var phoneticDepth = 0

    private enum Capture { case value, inline }

    init(sharedStrings: [String], formatter: ExcelReader.CellFormatter) {
        self.sharedStrings = sharedStrings
        self.formatter = formatter
    }

    func table() -> ImportTable? {
        ExcelReader.table(from: rows)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "row":
            row = [:]
            column = -1
        case "c":
            column = attributes["r"].flatMap(Self.columnIndex) ?? column + 1
            cellType = attributes["t"]
            cellStyle = attributes["s"].flatMap(Int.init)
            value = ""
            inline = ""
        case "v":
            capturing = .value
        case "rPh":
            phoneticDepth += 1
        case "t" where phoneticDepth == 0:
            capturing = .inline
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch capturing {
        case .value: value += string
        case .inline: inline += string
        case nil: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "v", "t":
            capturing = nil
        case "rPh":
            phoneticDepth -= 1
        case "c":
            let text = cellText()
            if !text.isEmpty, column >= 0 { row[column] = text }
        case "row":
            rows.append(row)
        default:
            break
        }
    }

    private func cellText() -> String {
        switch cellType {
        case "s": Int(value).flatMap { sharedStrings.indices.contains($0) ? sharedStrings[$0] : nil } ?? ""
        case "inlineStr": XLSXReader.unescape(inline)
        case "str": XLSXReader.unescape(value)
        case "b": value == "1" ? "TRUE" : "FALSE"
        case "e": ""
        // An ISO 8601 date cell (Strict OOXML); the day is all a field keeps.
        case "d": String(value.prefix { $0 != "T" })
        default: value.isEmpty ? "" : Double(value).map { formatter.text(for: $0, style: cellStyle) } ?? value
        }
    }

    /// `AB12` → 27.
    static func columnIndex(_ reference: String) -> Int? {
        var index = 0
        var sawLetter = false
        for scalar in reference.unicodeScalars {
            guard let letter = UInt8(exactly: scalar.value), (65...90).contains(letter) || (97...122).contains(letter) else { break }
            index = index * 26 + Int(letter & 0x1F)
            sawLetter = true
        }
        return sawLetter ? index - 1 : nil
    }
}
