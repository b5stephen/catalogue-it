//
//  ZipArchive.swift
//  catalogue-it
//

import Compression
import Foundation

// MARK: - Zip Archive

/// Reads entries of an in-memory zip archive: stored or deflated, no Zip64, no encryption —
/// which covers every Office Open XML file. Foundation has no public zip reader.
nonisolated struct ZipArchive {

    enum ReadError: Error {
        case notAZip
        case damaged
        case unsupported
    }

    private struct Entry {
        let method: UInt16
        let flags: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Guards against a small file that inflates to gigabytes.
    static let maximumEntrySize = 256 * 1024 * 1024

    private let data: Data
    private let entries: [String: Entry]

    var paths: Set<String> { Set(entries.keys) }

    static func isZip(_ data: Data) -> Bool {
        data.starts(with: [0x50, 0x4B, 0x03, 0x04])
    }

    init(_ data: Data) throws {
        // Index from zero: a Data slice keeps its parent's indices.
        let data = Data(data)
        guard Self.isZip(data) else { throw ReadError.notAZip }
        self.data = data

        // The end-of-central-directory record is last, followed by a comment of up to 64 KB.
        let earliest = max(0, data.count - 22 - 0xFFFF)
        guard var end = data.count >= 22 ? data.count - 22 : nil else { throw ReadError.damaged }
        while data.uint32(at: end) != 0x0605_4B50 {
            guard end > earliest else { throw ReadError.damaged }
            end -= 1
        }
        let count = Int(data.uint16(at: end + 10))
        let directoryOffset = Int(data.uint32(at: end + 16))
        guard count != 0xFFFF, directoryOffset != 0xFFFF_FFFF else { throw ReadError.unsupported }

        var entries: [String: Entry] = [:]
        var offset = directoryOffset
        for _ in 0..<count {
            guard offset + 46 <= data.count, data.uint32(at: offset) == 0x0201_4B50 else { throw ReadError.damaged }
            let nameLength = Int(data.uint16(at: offset + 28))
            let extraLength = Int(data.uint16(at: offset + 30))
            let commentLength = Int(data.uint16(at: offset + 32))
            guard offset + 46 + nameLength <= data.count else { throw ReadError.damaged }
            let name = String(decoding: data[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            entries[name] = Entry(
                method: data.uint16(at: offset + 10),
                flags: data.uint16(at: offset + 8),
                compressedSize: Int(data.uint32(at: offset + 20)),
                uncompressedSize: Int(data.uint32(at: offset + 24)),
                localHeaderOffset: Int(data.uint32(at: offset + 42)))
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// The entry's contents, or nil when the archive has no such path. A leading `/` is ignored.
    func contents(of path: String) throws -> Data? {
        let key = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let entry = entries[key] else { return nil }
        guard entry.flags & 0x1 == 0 else { throw ReadError.unsupported }
        guard entry.compressedSize != 0xFFFF_FFFF, entry.uncompressedSize <= Self.maximumEntrySize else {
            throw ReadError.unsupported
        }

        // Sizes come from the central directory: the local header's may be zero when a data
        // descriptor follows the entry.
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, data.uint32(at: header) == 0x0403_4B50 else { throw ReadError.damaged }
        let start = header + 30 + Int(data.uint16(at: header + 26)) + Int(data.uint16(at: header + 28))
        guard start + entry.compressedSize <= data.count else { throw ReadError.damaged }
        let compressed = data[start..<(start + entry.compressedSize)]

        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            return try Self.inflate(compressed, size: entry.uncompressedSize)
        default:
            throw ReadError.unsupported
        }
    }

    /// `COMPRESSION_ZLIB` is raw DEFLATE (RFC 1951), which is what zip stores.
    private static func inflate(_ compressed: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        guard !compressed.isEmpty else { throw ReadError.damaged }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ReadError.damaged }
        return output
    }
}

// MARK: - Little-Endian Reads

extension Data {
    nonisolated func uint16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    nonisolated func uint32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
