//
//  DelimitedTextParser.swift
//  catalogue-it
//

import Foundation

// MARK: - Import Table

/// Rows of cells as read, every row padded to the same width. Whether the first row is a header
/// is the user's call, so it stays a row here.
nonisolated struct ImportTable: Equatable, Sendable {
    var rows: [[String]]

    var columnCount: Int { rows.first?.count ?? 0 }
}

// MARK: - Delimited Text Parser

/// Reads CSV, TSV and semicolon-separated text: RFC 4180 quoting (quoted line breaks and `""`
/// escapes), CRLF or LF. The delimiter is worked out from the text, so a European Excel file
/// (`;`) and a paste from Numbers (tab) need no setting.
nonisolated enum DelimitedTextParser {

    enum ParseError: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "The file isn’t text that Catalogue-It can read.")
            case .empty: String(localized: "There are no rows to import.")
            }
        }
    }

    static func parse(_ data: Data) throws -> ImportTable {
        guard let text = decode(data) else { throw ParseError.unreadable }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> ImportTable {
        let delimiter = sniffDelimiter(in: text)
        var rows = split(text, delimiter: delimiter)
        rows.removeAll { $0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !rows.isEmpty else { throw ParseError.empty }
        let width = rows.map(\.count).max() ?? 0
        rows = rows.map { $0.count < width ? $0 + Array(repeating: "", count: width - $0.count) : $0 }
        return ImportTable(rows: rows)
    }

    // MARK: Encoding

    /// UTF-8 (with or without a byte order mark), UTF-16 with a byte order mark, then the two
    /// single-byte encodings older spreadsheet apps write.
    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        let body = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        if let text = String(data: body, encoding: .utf8) { return text }
        return String(data: body, encoding: .windowsCP1252) ?? String(data: body, encoding: .macOSRoman)
    }

    // MARK: Delimiter

    /// Of tab, comma and semicolon, the one that splits the first rows into the same number of
    /// columns most often, then into the most; ties go to the earlier. A comma in quoted text
    /// doesn't count, and a single column means the text has no delimiter at all.
    static func sniffDelimiter(in text: String) -> Character {
        let candidates: [Character] = ["\t", ",", ";"]
        let prefix = text.prefix(16_384)
        let sample = String(prefix)
        let isTruncated = prefix.endIndex < text.endIndex
        var best: Character = ","
        var bestScore = 0
        for candidate in candidates {
            var rows = split(sample, delimiter: candidate)
            // The sample may cut the last row short.
            if isTruncated, rows.count > 1 { rows.removeLast() }
            let counts = rows.prefix(10).map(\.count)
            guard let first = counts.first, first > 1 else { continue }
            let score = counts.filter { $0 == first }.count * 1_000 + first
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    // MARK: Splitting

    /// With an absent delimiter (NUL) each row is one cell: the raw line, quotes resolved.
    private static func split(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var inQuotes = false
        var atCellStart = true
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?
        let delimiterScalar = delimiter.unicodeScalars.first!

        func endCell() {
            row.append(cell)
            cell = ""
            atCellStart = true
        }
        func endRow() {
            endCell()
            rows.append(row)
            row = []
        }

        while let scalar = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if scalar == "\"" {
                    let next = iterator.next()
                    if next == "\"" {
                        cell.unicodeScalars.append("\"")
                    } else {
                        inQuotes = false
                        pending = next
                    }
                } else {
                    cell.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where atCellStart:
                inQuotes = true
                atCellStart = false
            case delimiterScalar:
                endCell()
            case "\r":
                let next = iterator.next()
                if next != "\n" { pending = next }
                endRow()
            case "\n":
                endRow()
            default:
                cell.unicodeScalars.append(scalar)
                atCellStart = false
            }
        }
        if !cell.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
