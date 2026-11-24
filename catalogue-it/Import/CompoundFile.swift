//
//  CompoundFile.swift
//  catalogue-it
//

import Foundation

// MARK: - Compound File

/// Reads the top-level streams of an OLE compound file ([MS-CFB]), the container of .xls
/// workbooks and of password-protected Office files.
nonisolated struct CompoundFile {

    enum ReadError: Error {
        case damaged
    }

    private struct Stream {
        let start: UInt32
        let size: Int
    }

    private static let endOfChain: UInt32 = 0xFFFF_FFFE
    private static let freeSector: UInt32 = 0xFFFF_FFFF

    private let data: Data
    private let sectorSize: Int
    private let fat: [UInt32]
    private let miniFAT: [UInt32]
    private let miniStream: Data
    private let miniStreamCutoff: Int
    private let streams: [String: Stream]

    var streamNames: Set<String> { Set(streams.keys) }

    static func isCompoundFile(_ data: Data) -> Bool {
        data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    }

    init(_ data: Data) throws {
        // Index from zero: a Data slice keeps its parent's indices.
        let data = Data(data)
        guard Self.isCompoundFile(data), data.count >= 512, data.uint16(at: 28) == 0xFFFE else { throw ReadError.damaged }
        let majorVersion = data.uint16(at: 26)
        let sectorShift = Int(data.uint16(at: 30))
        let miniSectorShift = Int(data.uint16(at: 32))
        guard (majorVersion == 3 && sectorShift == 9) || (majorVersion == 4 && sectorShift == 12), miniSectorShift == 6 else {
            throw ReadError.damaged
        }
        self.data = data
        sectorSize = 1 << sectorShift
        miniStreamCutoff = Int(data.uint32(at: 56))

        // The FAT's own sectors are listed by the DIFAT: 109 entries in the header, then a
        // chain of DIFAT sectors whose last entry points to the next.
        var fatSectors = (0..<109).map { data.uint32(at: 76 + $0 * 4) }
        var difatSector = data.uint32(at: 68)
        let entriesPerSector = sectorSize / 4
        var visited = 0
        while difatSector != Self.endOfChain, difatSector != Self.freeSector {
            visited += 1
            let offset = (Int(difatSector) + 1) * sectorSize
            guard visited <= data.count / sectorSize, offset + sectorSize <= data.count else { throw ReadError.damaged }
            fatSectors += (0..<(entriesPerSector - 1)).map { data.uint32(at: offset + $0 * 4) }
            difatSector = data.uint32(at: offset + sectorSize - 4)
        }
        var fat: [UInt32] = []
        for sector in fatSectors.prefix(Int(data.uint32(at: 44))) where sector != Self.freeSector {
            let offset = (Int(sector) + 1) * sectorSize
            guard offset + sectorSize <= data.count else { throw ReadError.damaged }
            fat += (0..<entriesPerSector).map { data.uint32(at: offset + $0 * 4) }
        }
        self.fat = fat

        let directory = try Self.chain(from: data.uint32(at: 48), in: fat, sectorSize: sectorSize, data: data)
        guard directory.count >= 128 else { throw ReadError.damaged }
        func entry(_ id: UInt32) -> (name: String, type: UInt8, left: UInt32, right: UInt32, child: UInt32, stream: Stream)? {
            let offset = Int(id) * 128
            guard offset + 128 <= directory.count else { return nil }
            let nameLength = min(Int(directory.uint16(at: offset + 64)), 64)
            let units = (0..<max(0, nameLength / 2 - 1)).map { directory.uint16(at: offset + $0 * 2) }
            // Version 3 files may leave junk in the size's high half.
            let size = majorVersion == 3 ? Int(directory.uint32(at: offset + 120))
                : Int(directory.uint32(at: offset + 120)) | Int(directory.uint32(at: offset + 124)) << 32
            return (String(decoding: units, as: UTF16.self), directory[offset + 66],
                    directory.uint32(at: offset + 68), directory.uint32(at: offset + 72), directory.uint32(at: offset + 76),
                    Stream(start: directory.uint32(at: offset + 116), size: size))
        }
        guard let root = entry(0), root.type == 5 else { throw ReadError.damaged }

        let miniFATData = try Self.chain(from: data.uint32(at: 60), in: fat, sectorSize: sectorSize, data: data)
        miniFAT = (0..<(miniFATData.count / 4)).map { miniFATData.uint32(at: $0 * 4) }
        miniStream = try Self.chain(from: root.stream.start, in: fat, sectorSize: sectorSize, data: data).prefix(root.stream.size)

        // The root's children form a tree through their left and right siblings.
        var streams: [String: Stream] = [:]
        var pending = [root.child]
        var seen: Set<UInt32> = []
        while let id = pending.popLast() {
            guard id != Self.freeSector, seen.insert(id).inserted, let node = entry(id) else { continue }
            if node.type == 2 { streams[node.name] = node.stream }
            pending += [node.left, node.right]
        }
        self.streams = streams
    }

    /// The stream's contents, or nil when the file has no such top-level stream.
    func stream(named name: String) throws -> Data? {
        guard let stream = streams[name] else { return nil }
        if stream.size < miniStreamCutoff {
            return try Self.chain(from: stream.start, in: miniFAT, sectorSize: 64, data: miniStream, headerSectors: 0)
                .prefix(stream.size)
        }
        return try Self.chain(from: stream.start, in: fat, sectorSize: sectorSize, data: data).prefix(stream.size)
    }

    /// The sectors of a chain, joined. Sector n of the file sits after the one-sector header.
    private static func chain(
        from start: UInt32, in table: [UInt32], sectorSize: Int, data: Data, headerSectors: Int = 1
    ) throws -> Data {
        var result = Data()
        var sector = start
        var steps = 0
        while sector != endOfChain {
            steps += 1
            let offset = (Int(sector) + headerSectors) * sectorSize
            guard Int(sector) < table.count, steps <= table.count, offset + sectorSize <= data.count else {
                // A file may stop short of the last sector's padding.
                if offset < data.count, table.indices.contains(Int(sector)), table[Int(sector)] == endOfChain {
                    result.append(data[offset...])
                    break
                }
                throw ReadError.damaged
            }
            result.append(data[offset..<(offset + sectorSize)])
            sector = table[Int(sector)]
        }
        return result
    }
}
