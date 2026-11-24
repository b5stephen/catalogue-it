//
//  XLSReader.swift
//  catalogue-it
//

import Foundation

// MARK: - XLS Reader

/// Excel 97–2003 workbooks (.xls): BIFF8 records in a compound file's `Workbook` stream
/// ([MS-XLS]). Only cell values and the number formats that decide how they read are used.
nonisolated enum XLSReader {

    /// Visible worksheets with at least one value, in workbook order.
    static func sheets(_ data: Data) throws -> [ExcelReader.Sheet] {
        let file = try CompoundFile(data)
        // Office 2007+ encryption wraps the whole package in a compound file.
        if file.streamNames.contains("EncryptedPackage") { throw ExcelReader.ReadError.passwordProtected }
        guard let stream = try file.stream(named: "Workbook") else {
            // Excel 5 and 95 (BIFF5/7) name it `Book` and keep strings in a code page.
            throw file.streamNames.contains("Book") ? ExcelReader.ReadError.legacyFormat : ExcelReader.ReadError.notAWorkbook
        }

        let globals = try Globals(stream)
        let formatter = ExcelReader.CellFormatter(
            styles: globals.cellFormats.map { ExcelReader.CellFormatter.Style(code: globals.formatCode(for: $0)) },
            uses1904Dates: globals.uses1904Dates)
        return try globals.sheets.compactMap { sheet in
            guard sheet.isVisibleWorksheet,
                  let table = try cells(in: stream, from: sheet.offset, strings: globals.sharedStrings, formatter: formatter)
            else { return nil }
            return ExcelReader.Sheet(name: sheet.name, table: table)
        }
    }

    // MARK: Records

    private enum RecordType {
        static let bof: UInt16 = 0x0809
        static let eof: UInt16 = 0x000A
        static let filePass: UInt16 = 0x002F
        static let dateMode: UInt16 = 0x0022
        static let format: UInt16 = 0x041E
        static let xf: UInt16 = 0x00E0
        static let boundSheet: UInt16 = 0x0085
        static let sst: UInt16 = 0x00FC
        static let `continue`: UInt16 = 0x003C
        static let labelSST: UInt16 = 0x00FD
        static let label: UInt16 = 0x0204
        static let richString: UInt16 = 0x00D6
        static let number: UInt16 = 0x0203
        static let rk: UInt16 = 0x027E
        static let mulRK: UInt16 = 0x00BD
        static let boolErr: UInt16 = 0x0205
        static let formula: UInt16 = 0x0006
        static let string: UInt16 = 0x0207
    }

    private struct Record {
        let type: UInt16
        /// Zero-indexed.
        let body: Data
    }

    /// Records from `offset` to the end of the stream.
    private struct Records: Sequence, IteratorProtocol {
        let stream: Data
        var offset: Int

        mutating func next() -> Record? {
            guard offset + 4 <= stream.count else { return nil }
            let length = Int(stream.uint16(at: offset + 2))
            let start = offset + 4
            guard start + length <= stream.count else { return nil }
            defer { offset = start + length }
            return Record(type: stream.uint16(at: offset), body: Data(stream[start..<(start + length)]))
        }
    }

    // MARK: Workbook Globals

    private struct Globals {
        struct SheetEntry {
            let name: String
            let offset: Int
            let isVisibleWorksheet: Bool
        }

        private(set) var sheets: [SheetEntry] = []
        private(set) var sharedStrings: [String] = []
        private(set) var cellFormats: [Int] = []
        private(set) var uses1904Dates = false
        private var customCodes: [Int: String] = [:]

        func formatCode(for id: Int) -> String {
            customCodes[id] ?? ExcelReader.builtInFormatCode(id)
        }

        init(_ stream: Data) throws {
            var records = Records(stream: stream, offset: 0)
            guard let bof = records.next(), bof.type == RecordType.bof else { throw ExcelReader.ReadError.notAWorkbook }
            guard bof.body.uint16(at: 0) == 0x0600 else { throw ExcelReader.ReadError.legacyFormat }

            var sst: [Data] = []
            var inSST = false
            while let record = records.next(), record.type != RecordType.eof {
                if inSST, record.type == RecordType.continue {
                    sst.append(record.body)
                    continue
                }
                inSST = false
                switch record.type {
                case RecordType.filePass:
                    throw ExcelReader.ReadError.passwordProtected
                case RecordType.dateMode:
                    uses1904Dates = record.body.uint16(at: 0) == 1
                case RecordType.format:
                    var reader = SegmentReader([record.body.dropFirst(2)])
                    customCodes[Int(record.body.uint16(at: 0))] = try reader.string()
                case RecordType.xf:
                    // Style and cell XFs share one list; a cell's index counts both.
                    cellFormats.append(Int(record.body.uint16(at: 2)))
                case RecordType.boundSheet:
                    guard record.body.count >= 8 else { continue }
                    var reader = SegmentReader([record.body.dropFirst(6)])
                    sheets.append(SheetEntry(
                        name: try reader.string(lengthBytes: 1),
                        offset: Int(record.body.uint32(at: 0)),
                        // Visible (state 0) and a worksheet (type 0), not a chart or macro sheet.
                        isVisibleWorksheet: record.body[4] & 0x03 == 0 && record.body[5] == 0))
                case RecordType.sst:
                    sst = [record.body.dropFirst(8)]
                    inSST = true
                default:
                    break
                }
            }

            guard !sst.isEmpty else { return }
            var reader = SegmentReader(sst)
            while !reader.isAtEnd {
                sharedStrings.append(try reader.string())
            }
        }
    }

    // MARK: Worksheet Cells

    private static func cells(
        in stream: Data, from offset: Int, strings: [String], formatter: ExcelReader.CellFormatter
    ) throws -> ImportTable? {
        var records = Records(stream: stream, offset: offset)
        guard let bof = records.next(), bof.type == RecordType.bof, bof.body.uint16(at: 2) == 0x0010 else { return nil }

        var rows: [Int: [Int: String]] = [:]
        var pendingString: (row: Int, column: Int)?
        func set(_ text: String, row: UInt16, column: UInt16) {
            if !text.isEmpty { rows[Int(row), default: [:]][Int(column)] = text }
        }
        func number(_ value: Double, xf: UInt16) -> String {
            formatter.text(for: value, style: Int(xf))
        }

        while let record = records.next(), record.type != RecordType.eof {
            let body = record.body
            guard body.count >= 6 || record.type == RecordType.string else { continue }
            let row = body.uint16(at: 0)
            let column = body.uint16(at: 2)
            let xf = body.uint16(at: 4)
            switch record.type {
            case RecordType.labelSST:
                let index = Int(body.uint32(at: 6))
                if strings.indices.contains(index) { set(strings[index], row: row, column: column) }
            case RecordType.label, RecordType.richString:
                var reader = SegmentReader([body.dropFirst(6)])
                set(try reader.string(), row: row, column: column)
            case RecordType.number where body.count >= 14:
                set(number(body.double(at: 6), xf: xf), row: row, column: column)
            case RecordType.rk where body.count >= 10:
                set(number(rk(body.uint32(at: 6)), xf: xf), row: row, column: column)
            case RecordType.mulRK:
                // Six-byte (xf, rk) pairs from the first column, then the last column's index.
                let pairs = (body.count - 6) / 6
                for pair in 0..<max(0, pairs) {
                    let at = 4 + pair * 6
                    set(number(rk(body.uint32(at: at + 2)), xf: body.uint16(at: at)), row: row, column: column + UInt16(pair))
                }
            case RecordType.boolErr where body.count >= 8:
                // Errors are left empty.
                if body[7] == 0 { set(body[6] == 0 ? "FALSE" : "TRUE", row: row, column: column) }
            case RecordType.formula where body.count >= 14:
                // The cached result: a double, unless its top two bytes are 0xFFFF.
                if body.uint16(at: 12) == 0xFFFF {
                    switch body[6] {
                    case 0: pendingString = (Int(row), Int(column))
                    case 1: set(body[8] == 0 ? "FALSE" : "TRUE", row: row, column: column)
                    default: break
                    }
                } else {
                    set(number(body.double(at: 6), xf: xf), row: row, column: column)
                }
            case RecordType.string:
                guard let target = pendingString else { continue }
                pendingString = nil
                var reader = SegmentReader([body])
                set(try reader.string(), row: UInt16(target.row), column: UInt16(target.column))
            default:
                break
            }
        }
        return ExcelReader.table(from: rows.keys.sorted().map { rows[$0] ?? [:] })
    }

    /// A 30-bit integer or the top 30 bits of a double, optionally hundredths.
    static func rk(_ value: UInt32) -> Double {
        let number = value & 0x2 != 0
            ? Double(Int32(bitPattern: value) >> 2)
            : Double(bitPattern: UInt64(value & 0xFFFF_FFFC) << 32)
        return value & 0x1 != 0 ? number / 100 : number
    }

    // MARK: Strings

    /// Reads BIFF8 Unicode strings across a record and its `CONTINUE`s. A string's characters
    /// may break across records, and each continuation restarts with an options byte saying
    /// whether the rest is one or two bytes per character.
    private struct SegmentReader {
        private let segments: [Data]
        private var index = 0
        private var offset = 0

        init(_ segments: [Data]) {
            self.segments = segments.map { Data($0) }
        }

        var isAtEnd: Bool {
            var index = index
            var offset = offset
            while index < segments.count, offset >= segments[index].count {
                index += 1
                offset = 0
            }
            return index >= segments.count
        }

        private mutating func byte() throws -> UInt8 {
            while index < segments.count, offset >= segments[index].count {
                index += 1
                offset = 0
            }
            guard index < segments.count else { throw ExcelReader.ReadError.notAWorkbook }
            defer { offset += 1 }
            return segments[index][offset]
        }

        private mutating func uint16() throws -> UInt16 {
            UInt16(try byte()) | UInt16(try byte()) << 8
        }

        private mutating func uint32() throws -> UInt32 {
            UInt32(try uint16()) | UInt32(try uint16()) << 16
        }

        private mutating func skip(_ count: Int) throws {
            for _ in 0..<count { _ = try byte() }
        }

        /// An XLUnicodeRichExtendedString, or with a one-byte length a ShortXLUnicodeString.
        mutating func string(lengthBytes: Int = 2) throws -> String {
            let length = lengthBytes == 1 ? Int(try byte()) : Int(try uint16())
            let options = try byte()
            var isWide = options & 0x01 != 0
            let runs = options & 0x08 != 0 ? Int(try uint16()) : 0
            let extended = options & 0x04 != 0 ? Int(try uint32()) : 0

            var units: [UInt16] = []
            units.reserveCapacity(length)
            for _ in 0..<length {
                if offset >= segments[index].count, index + 1 < segments.count {
                    index += 1
                    offset = 0
                    isWide = try byte() & 0x01 != 0
                }
                units.append(isWide ? try uint16() : UInt16(try byte()))
            }
            try skip(runs * 4 + extended)
            return String(decoding: units, as: UTF16.self)
        }
    }
}

private extension Data {
    nonisolated func double(at offset: Int) -> Double {
        Double(bitPattern: UInt64(uint32(at: offset)) | UInt64(uint32(at: offset + 4)) << 32)
    }
}
