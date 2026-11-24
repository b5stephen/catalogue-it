//
//  XLSReaderTests.swift
//  UnitTests
//

import Foundation
import Testing
@testable import catalogue_it

struct XLSReaderTests {

    // MARK: Workbooks

    @Test("Cells of every record type read as the values Excel shows")
    func readsCells() throws {
        let sheets = try ExcelReader.read(compoundFile("Workbook", workbook()))
        #expect(sheets.map(\.name) == ["Planes"], "Hidden and chart sheets are left out")

        let rows = sheets[0].table.rows
        #expect(rows.count == 3, "The empty row between is dropped")
        #expect(rows[0] == ["Name", "Built", "Price", "Share", "Weight", "Flies", "Maker"])
        #expect(rows[1] == ["Spitfire Żuraw", "2023-03-15", "€12.50", "25", "3.00", "TRUE", "Supermarine"])
        #expect(rows[2] == ["Hurricane", "", "€-3.00", "", "", "FALSE", ""])
    }

    @Test("A workbook stream past the mini-stream cutoff is read from regular sectors")
    func largeWorkbook() throws {
        let stream = workbook(extraRows: 300)
        #expect(stream.count > 4_096)
        let rows = try ExcelReader.read(compoundFile("Workbook", stream))[0].table.rows
        #expect(rows.count == 303)
        #expect(rows.last?.first == "Row 300")
    }

    @Test("1904-based workbooks count days from 1904")
    func dates1904() throws {
        let rows = try ExcelReader.read(compoundFile("Workbook", workbook(uses1904Dates: true)))[0].table.rows
        #expect(rows[1][1] == "2027-03-16", "Serial 45000 is 1,462 days later than in the 1900 system")
    }

    @Test("RK values hold 30-bit integers or truncated doubles, optionally hundredths")
    func rkValues() {
        #expect(XLSReader.rk(3 << 2 | 0x2) == 3)
        #expect(XLSReader.rk(UInt32(bitPattern: -7 << 2) | 0x2) == -7)
        #expect(XLSReader.rk(1_250 << 2 | 0x3) == 12.5)
        #expect(XLSReader.rk(0x3FD0_0000) == 0.25)
    }

    // MARK: Other Files

    @Test("Encrypted, pre-97 and unrelated compound files say what to do instead")
    func unreadable() {
        #expect(throws: ExcelReader.ReadError.passwordProtected) {
            try ExcelReader.read(compoundFile("Workbook", workbook(isEncrypted: true)))
        }
        #expect(throws: ExcelReader.ReadError.passwordProtected) {
            try ExcelReader.read(compoundFile("EncryptedPackage", [1, 2, 3, 4]))
        }
        #expect(throws: ExcelReader.ReadError.legacyFormat) {
            try ExcelReader.read(compoundFile("Book", workbook()))
        }
        #expect(throws: ExcelReader.ReadError.legacyFormat) {
            try ExcelReader.read(compoundFile("Workbook", workbook(version: 0x0500)))
        }
        #expect(throws: ExcelReader.ReadError.notAWorkbook) {
            try ExcelReader.read(compoundFile("WordDocument", [1, 2, 3, 4]))
        }
    }

    // MARK: BIFF8 Fixture

    private func workbook(
        version: UInt16 = 0x0600, uses1904Dates: Bool = false, isEncrypted: Bool = false, extraRows: Int = 0
    ) -> [UInt8] {
        let planes = substream(type: 0x0010, worksheetRecords(extraRows: extraRows))
        let hidden = substream(type: 0x0010, record(0x0204, cell(0, 0, 0) + compressed("Secret")))
        let chart = substream(type: 0x0020, [])

        func globals(offsets: [Int]) -> [UInt8] {
            var records = bof(version: version, type: 0x0005)
            if isEncrypted { records += record(0x002F, le16(1) + Array(repeating: 0, count: 52)) }
            if uses1904Dates { records += record(0x0022, le16(1)) }
            records += record(0x041E, le16(164) + wide("[$€-407]#,##0.00"))
            for format in [0, 14, 164, 9, 2] {
                records += record(0x00E0, le16(0) + le16(format) + Array(repeating: 0, count: 16))
            }
            records += record(0x0085, le32(offsets[0]) + [0, 0] + compressed("Planes", lengthBytes: 1))
            records += record(0x0085, le32(offsets[1]) + [1, 0] + compressed("Hidden", lengthBytes: 1))
            records += record(0x0085, le32(offsets[2]) + [0, 2] + compressed("Chart", lengthBytes: 1))

            // "Spitfire Żuraw" breaks across the CONTINUE, switching to two-byte characters.
            let strings = ["Name", "Built", "Price", "Share", "Weight"].flatMap { compressed($0) }
                + le16(5) + [0x08] + le16(1) + Array("Flies".utf8) + [0, 0, 0, 0]
                + compressed("Maker")
                + le16(14) + [0x00] + Array("Spitfire ".utf8)
            records += record(0x00FC, le32(8) + le32(8) + strings)
            records += record(0x003C, [0x01] + "Żuraw".utf16.flatMap { le16(Int($0)) })
            return records + record(0x000A, [])
        }
        let globalsLength = globals(offsets: [0, 0, 0]).count
        let offsets = [globalsLength, globalsLength + planes.count, globalsLength + planes.count + hidden.count]
        return globals(offsets: offsets) + planes + hidden + chart
    }

    private func worksheetRecords(extraRows: Int) -> [UInt8] {
        var records: [UInt8] = []
        for column in 0..<7 {
            records += record(0x00FD, cell(0, column, 0) + le32(column))
        }
        records += record(0x00FD, cell(1, 0, 0) + le32(7))
        records += record(0x0203, cell(1, 1, 1) + f64(45_000))
        records += record(0x027E, cell(1, 2, 2) + le32(1_250 << 2 | 0x3))
        records += record(0x00BD, le16(1) + le16(3) + le16(3) + le32(0x3FD0_0000) + le16(4) + le32(3 << 2 | 0x2) + le16(4))
        records += record(0x0205, cell(1, 5, 0) + [1, 0])
        records += record(0x0006, cell(1, 6, 0) + [0, 0, 0, 0, 0, 0, 0xFF, 0xFF] + le16(0) + le32(0) + le16(0))
        records += record(0x0207, compressed("Supermarine"))

        records += record(0x0204, cell(3, 0, 0) + compressed("Hurricane"))
        records += record(0x0205, cell(3, 1, 0) + [0x2A, 1])
        records += record(0x0006, cell(3, 2, 2) + f64(-3) + le16(0) + le32(0) + le16(0))
        records += record(0x0006, cell(3, 5, 0) + [1, 0, 0, 0, 0, 0, 0xFF, 0xFF] + le16(0) + le32(0) + le16(0))

        for row in 0..<extraRows {
            records += record(0x0204, cell(10 + row, 0, 0) + compressed("Row \(row + 1)"))
        }
        return records
    }

    private func substream(type: UInt16, _ records: [UInt8]) -> [UInt8] {
        bof(version: 0x0600, type: type) + records + record(0x000A, [])
    }

    private func bof(version: UInt16, type: UInt16) -> [UInt8] {
        record(0x0809, le16(Int(version)) + le16(Int(type)) + Array(repeating: 0, count: 12))
    }

    private func record(_ type: UInt16, _ body: [UInt8]) -> [UInt8] {
        le16(Int(type)) + le16(body.count) + body
    }

    private func cell(_ row: Int, _ column: Int, _ xf: Int) -> [UInt8] {
        le16(row) + le16(column) + le16(xf)
    }

    private func compressed(_ text: String, lengthBytes: Int = 2) -> [UInt8] {
        let bytes = Array(text.unicodeScalars.map { UInt8($0.value) })
        return (lengthBytes == 1 ? [UInt8(bytes.count)] : le16(bytes.count)) + [0x00] + bytes
    }

    private func wide(_ text: String) -> [UInt8] {
        le16(text.utf16.count) + [0x01] + text.utf16.flatMap { le16(Int($0)) }
    }

    private func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
    private func le32(_ value: Int) -> [UInt8] { le16(value & 0xFFFF) + le16(value >> 16 & 0xFFFF) }
    private func f64(_ value: Double) -> [UInt8] {
        let bits = value.bitPattern
        return (0..<8).map { UInt8(bits >> ($0 * 8) & 0xFF) }
    }

    // MARK: Compound File Fixture

    /// A version 3 compound file holding one stream: FAT in sector 0, directory in sector 1,
    /// then either a mini FAT and the mini stream or the stream's own sectors.
    private func compoundFile(_ name: String, _ stream: [UInt8]) -> Data {
        let endOfChain = 0xFFFF_FFFE, free = 0xFFFF_FFFF
        let isMini = stream.count < 4_096
        func padded(_ bytes: [UInt8], to multiple: Int) -> [UInt8] {
            bytes + Array(repeating: 0, count: (multiple - bytes.count % multiple) % multiple)
        }

        let content = isMini ? padded(stream, to: 64) : stream
        let dataSectors = (padded(content, to: 512).count) / 512
        let firstData = isMini ? 3 : 2
        var fat = [0xFFFF_FFFD, endOfChain] + (isMini ? [endOfChain] : [])
        fat += (0..<dataSectors).map { $0 == dataSectors - 1 ? endOfChain : firstData + $0 + 1 }
        fat += Array(repeating: free, count: 128 - fat.count)

        var header: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] + Array(repeating: 0, count: 16)
        header += le16(0x3E) + le16(3) + le16(0xFFFE) + le16(9) + le16(6) + Array(repeating: 0, count: 6)
        header += le32(0) + le32(1) + le32(1) + le32(0) + le32(4_096)
        header += le32(isMini ? 2 : endOfChain) + le32(isMini ? 1 : 0) + le32(endOfChain) + le32(0)
        header += le32(0) + (1..<109).flatMap { _ in le32(free) }

        func entry(_ name: String, type: UInt8, child: Int, start: Int, size: Int) -> [UInt8] {
            let units = name.utf16.flatMap { le16(Int($0)) }
            return Array(padded(units, to: 64).prefix(64)) + le16((name.utf16.count + 1) * 2) + [type, 1]
                + le32(free) + le32(free) + le32(child) + Array(repeating: 0, count: 36)
                + le32(start) + le32(size) + le32(0)
        }
        let root = entry("Root Entry", type: 5, child: 1, start: isMini ? firstData : endOfChain, size: isMini ? content.count : 0)
        let file = entry(name, type: 2, child: free, start: isMini ? 0 : firstData, size: stream.count)
        let directory = root + file + Array(repeating: 0, count: 256)

        var sectors = fat.flatMap { le32($0) } + directory
        if isMini {
            let miniSectors = content.count / 64
            let miniFAT = (0..<miniSectors).map { $0 == miniSectors - 1 ? endOfChain : $0 + 1 }
            sectors += padded((miniFAT + Array(repeating: free, count: 128 - miniSectors)).flatMap { le32($0) }, to: 512)
        }
        sectors += padded(content, to: 512)
        return Data(header + sectors)
    }
}
