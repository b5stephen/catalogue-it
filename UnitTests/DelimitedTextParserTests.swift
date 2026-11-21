//
//  DelimitedTextParserTests.swift
//  UnitTests
//

import Testing
import Foundation
@testable import catalogue_it

struct DelimitedTextParserTests {

    @Test("Quoted cells keep commas, line breaks and escaped quotes")
    func quoting() throws {
        let text = "Name,Notes\r\n\"Spitfire, Mk IX\",\"Two\nlines\"\r\nHurricane,\"Says \"\"hi\"\"\"\r\n"
        let table = try DelimitedTextParser.parse(text)
        #expect(table.rows == [
            ["Name", "Notes"],
            ["Spitfire, Mk IX", "Two\nlines"],
            ["Hurricane", "Says \"hi\""],
        ])
    }

    @Test("Semicolons and tabs are recognised as the delimiter", arguments: [";", "\t"])
    func sniffsDelimiter(_ delimiter: String) throws {
        let text = ["Name", "Price"].joined(separator: delimiter) + "\n" + ["Spitfire", "12,50"].joined(separator: delimiter) + "\n"
        let table = try DelimitedTextParser.parse(text)
        #expect(table.rows == [["Name", "Price"], ["Spitfire", "12,50"]])
    }

    @Test("A comma inside quotes doesn't outvote the semicolon")
    func quotedCommaIgnoredWhenSniffing() throws {
        let text = "Name;Notes\n\"A, B, C\";x\n\"D, E\";y\n"
        #expect(DelimitedTextParser.sniffDelimiter(in: text) == ";")
    }

    @Test("A single column has no delimiter")
    func singleColumn() throws {
        let table = try DelimitedTextParser.parse("Spitfire\nHurricane\n")
        #expect(table.rows == [["Spitfire"], ["Hurricane"]])
    }

    @Test("Short rows are padded and blank rows dropped")
    func raggedRows() throws {
        let table = try DelimitedTextParser.parse("a,b,c\n\n1\n , \n2,3\n")
        #expect(table.rows == [["a", "b", "c"], ["1", "", ""], ["2", "3", ""]])
    }

    @Test("Byte order marks and older single-byte encodings are read")
    func encodings() throws {
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("Name\nCafé\n".utf8)
        #expect(try DelimitedTextParser.parse(bom).rows == [["Name"], ["Café"]])

        let cp1252 = try #require("Name\nCafé\n".data(using: .windowsCP1252))
        #expect(try DelimitedTextParser.parse(cp1252).rows == [["Name"], ["Café"]])

        let utf16 = try #require("Name\tYear\nSpitfire\t1938\n".data(using: .utf16))
        #expect(try DelimitedTextParser.parse(utf16).rows == [["Name", "Year"], ["Spitfire", "1938"]])
    }

    @Test("Text with no rows is an error")
    func emptyText() {
        #expect(throws: DelimitedTextParser.ParseError.self) { try DelimitedTextParser.parse(" \n\n") }
    }
}
