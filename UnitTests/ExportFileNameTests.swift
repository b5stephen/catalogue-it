//
//  ExportFileNameTests.swift
//  UnitTests
//

import Foundation
import Testing
@testable import catalogue_it

struct ExportFileNameTests {
    @Test("The stamp is the local wall-clock time, zero-padded, with no colon")
    func stampIsLocalAndPadded() throws {
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let honolulu = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        let instant = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC
        #expect(ExportFileName.stamp(instant, timeZone: auckland) == "2023-11-15 11.13")
        #expect(ExportFileName.stamp(instant, timeZone: honolulu) == "2023-11-14 12.13")

        let utc = try #require(TimeZone(identifier: "UTC"))
        let early = Date(timeIntervalSince1970: 1_704_330_300) // 2024-01-04 01:05 UTC
        #expect(ExportFileName.stamp(early, timeZone: utc) == "2024-01-04 01.05")
    }

    @Test("Exports a minute apart get different names")
    func namesDiffer() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let names = [first, first.addingTimeInterval(60)].map {
            ExportFileName.make(catalogueName: "Planes", exportedAt: $0, timeZone: utc, pathExtension: "csv")
        }
        #expect(names[0] != names[1])
    }
}
