//
//  SortKeyEncoderTiebreakTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Helpers

/// Creates an in-memory SwiftData container for tiebreak-key testing.
@MainActor
private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Catalogue.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

@MainActor
private let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
    return f
}()

// MARK: - Tiebreak Key Tests

@MainActor
struct SortKeyEncoderTiebreakTests {

    // MARK: - Own field excluded, other fields included in priority order

    @Test("tiebreakKey excludes the field's own value and includes others in priority order")
    func excludesOwnFieldIncludesOthers() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        let fieldA = FieldDefinition(name: "A", fieldType: .text, priority: 0)
        let fieldB = FieldDefinition(name: "B", fieldType: .text, priority: 1)
        fieldA.catalogue = catalogue
        fieldB.catalogue = catalogue
        ctx.insert(fieldA)
        ctx.insert(fieldB)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)

        let fvA = FieldValue(fieldDefinition: fieldA, fieldType: .text)
        fvA.textValue = "X"
        fvA.item = item
        ctx.insert(fvA)

        let fvB = FieldValue(fieldDefinition: fieldB, fieldType: .text)
        fvB.textValue = "Y"
        fvB.item = item
        ctx.insert(fvB)

        let keyForA = SortKeyEncoder.tiebreakKey(
            for: fvA,
            allFieldValuesOnItem: [fvA, fvB],
            fieldDefinitionsByPriority: [fieldA, fieldB],
            itemCreatedDate: item.createdDate
        )
        let expectedForA = "y" + SortKeyEncoder.tiebreakSeparator + iso8601.string(from: item.createdDate)
        #expect(keyForA == expectedForA, "A's tiebreak key should embed B's value, not its own")

        let keyForB = SortKeyEncoder.tiebreakKey(
            for: fvB,
            allFieldValuesOnItem: [fvA, fvB],
            fieldDefinitionsByPriority: [fieldA, fieldB],
            itemCreatedDate: item.createdDate
        )
        let expectedForB = "x" + SortKeyEncoder.tiebreakSeparator + iso8601.string(from: item.createdDate)
        #expect(keyForB == expectedForB, "B's tiebreak key should embed A's value, not its own")
    }

    // MARK: - Missing sibling value

    @Test("tiebreakKey uses missingValueSentinel for a field with no FieldValue row")
    func missingSiblingValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        let fieldA = FieldDefinition(name: "A", fieldType: .text, priority: 0)
        let fieldB = FieldDefinition(name: "B", fieldType: .text, priority: 1)
        fieldA.catalogue = catalogue
        fieldB.catalogue = catalogue
        ctx.insert(fieldA)
        ctx.insert(fieldB)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)

        let fvA = FieldValue(fieldDefinition: fieldA, fieldType: .text)
        fvA.textValue = "X"
        fvA.item = item
        ctx.insert(fvA)
        // No FieldValue created for fieldB — item has no value for it.

        let key = SortKeyEncoder.tiebreakKey(
            for: fvA,
            allFieldValuesOnItem: [fvA],
            fieldDefinitionsByPriority: [fieldA, fieldB],
            itemCreatedDate: item.createdDate
        )
        let expected = SortKeyEncoder.missingValueSentinel + SortKeyEncoder.tiebreakSeparator + iso8601.string(from: item.createdDate)
        #expect(key == expected)
    }

    // MARK: - Screenshot scenario: Airline tie broken by Aircraft

    @Test("Airline tie is broken by Aircraft, matching the reported bug's expected order")
    func airlineTiedBrokenByAircraft() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Plane Sorter", iconName: "airplane", colorHex: "#000000")
        ctx.insert(catalogue)
        let airlineDef = FieldDefinition(name: "Airline", fieldType: .text, priority: 0)
        let aircraftDef = FieldDefinition(name: "Aircraft", fieldType: .text, priority: 1)
        airlineDef.catalogue = catalogue
        aircraftDef.catalogue = catalogue
        ctx.insert(airlineDef)
        ctx.insert(aircraftDef)

        func makeAirlineFieldValue(aircraft: String?, createdDate: Date) -> FieldValue {
            let item = CatalogueItem()
            item.catalogue = catalogue
            item.createdDate = createdDate
            ctx.insert(item)

            let airlineFV = FieldValue(fieldDefinition: airlineDef, fieldType: .text)
            airlineFV.textValue = "Air New Zealand"
            airlineFV.item = item
            ctx.insert(airlineFV)

            var siblings = [airlineFV]
            if let aircraft {
                let aircraftFV = FieldValue(fieldDefinition: aircraftDef, fieldType: .text)
                aircraftFV.textValue = aircraft
                aircraftFV.item = item
                ctx.insert(aircraftFV)
                siblings.append(aircraftFV)
            }

            airlineFV.tiebreakKey = SortKeyEncoder.tiebreakKey(
                for: airlineFV,
                allFieldValuesOnItem: siblings,
                fieldDefinitionsByPriority: [airlineDef, aircraftDef],
                itemCreatedDate: item.createdDate
            )
            return airlineFV
        }

        // Mirrors the screenshot: three "Air New Zealand" items, differing Aircraft.
        let sameDate = Date(timeIntervalSince1970: 0)
        let fv777 = makeAirlineFieldValue(aircraft: "777-319 ER", createdDate: sameDate)
        let fv787 = makeAirlineFieldValue(aircraft: "787-9", createdDate: sameDate)
        let fvMissing = makeAirlineFieldValue(aircraft: nil, createdDate: sameDate)

        // Plain string comparison — this is exactly what the DB-level SortDescriptor does.
        #expect(fv777.tiebreakKey < fv787.tiebreakKey, "777-319 ER should sort before 787-9")
        #expect(fv787.tiebreakKey < fvMissing.tiebreakKey, "A present Aircraft value should sort before a missing one")
    }

    // MARK: - Full tie cascades down to createdDate

    @Test("Fully tied items fall back to createdDate as the final tiebreaker")
    func fullTieFallsBackToCreatedDate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        let fieldA = FieldDefinition(name: "A", fieldType: .text, priority: 0)
        fieldA.catalogue = catalogue
        ctx.insert(fieldA)

        func makeFieldValue(createdDate: Date) -> FieldValue {
            let item = CatalogueItem()
            item.catalogue = catalogue
            item.createdDate = createdDate
            ctx.insert(item)
            let fv = FieldValue(fieldDefinition: fieldA, fieldType: .text)
            fv.textValue = "Same"
            fv.item = item
            ctx.insert(fv)
            fv.tiebreakKey = SortKeyEncoder.tiebreakKey(
                for: fv,
                allFieldValuesOnItem: [fv],
                fieldDefinitionsByPriority: [fieldA],
                itemCreatedDate: item.createdDate
            )
            return fv
        }

        let older = makeFieldValue(createdDate: Date(timeIntervalSince1970: 0))
        let newer = makeFieldValue(createdDate: Date(timeIntervalSince1970: 1000))

        #expect(older.tiebreakKey < newer.tiebreakKey, "Older createdDate should sort first")
    }

    // MARK: - Separator does not collide with sentinel-valued content

    @Test("The tiebreak separator does not corrupt ordering when text contains the missing-value sentinel character")
    func separatorDoesNotCollideWithSentinelContent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        let fieldA = FieldDefinition(name: "A", fieldType: .text, priority: 0)
        let fieldB = FieldDefinition(name: "B", fieldType: .text, priority: 1)
        fieldA.catalogue = catalogue
        fieldB.catalogue = catalogue
        ctx.insert(fieldA)
        ctx.insert(fieldB)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)

        let fvA = FieldValue(fieldDefinition: fieldA, fieldType: .text)
        // Adversarial: a real value containing the sentinel character used for "missing".
        fvA.textValue = "z\u{FFFF}z"
        fvA.item = item
        ctx.insert(fvA)

        let key = SortKeyEncoder.tiebreakKey(
            for: fvA,
            allFieldValuesOnItem: [fvA],
            fieldDefinitionsByPriority: [fieldA, fieldB],
            itemCreatedDate: item.createdDate
        )
        // fieldB has no value at all — its segment should still be the plain sentinel,
        // distinguishable from fieldA's real (but adversarial) content since the separator
        // sorts below both.
        let expected = SortKeyEncoder.missingValueSentinel + SortKeyEncoder.tiebreakSeparator + iso8601.string(from: item.createdDate)
        #expect(key == expected)
    }

    // MARK: - Persistence round-trip

    @Test("tiebreakKey with multiple segments survives a save-and-refetch round trip intact")
    func survivesPersistenceRoundTrip() throws {
        // Regression guard: an earlier separator choice ("\u{0000}", NUL) was silently
        // truncated by SwiftData's persisted String storage, discarding every segment
        // after the first. This proves a multi-segment key comes back byte-for-byte equal
        // after an actual save + fetch, not just when compared in memory.
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Test", iconName: "star", colorHex: "#000000")
        ctx.insert(catalogue)
        let fieldA = FieldDefinition(name: "A", fieldType: .text, priority: 0)
        let fieldB = FieldDefinition(name: "B", fieldType: .text, priority: 1)
        let fieldC = FieldDefinition(name: "C", fieldType: .text, priority: 2)
        fieldA.catalogue = catalogue
        fieldB.catalogue = catalogue
        fieldC.catalogue = catalogue
        ctx.insert(fieldA)
        ctx.insert(fieldB)
        ctx.insert(fieldC)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)

        let fvA = FieldValue(fieldDefinition: fieldA, fieldType: .text)
        fvA.textValue = "X"
        fvA.item = item
        ctx.insert(fvA)

        let fvB = FieldValue(fieldDefinition: fieldB, fieldType: .text)
        fvB.textValue = "Y"
        fvB.item = item
        ctx.insert(fvB)

        let fvC = FieldValue(fieldDefinition: fieldC, fieldType: .text)
        fvC.textValue = "Z"
        fvC.item = item
        ctx.insert(fvC)

        let all = [fvA, fvB, fvC]
        let expectedKey = SortKeyEncoder.tiebreakKey(
            for: fvA,
            allFieldValuesOnItem: all,
            fieldDefinitionsByPriority: [fieldA, fieldB, fieldC],
            itemCreatedDate: item.createdDate
        )
        fvA.tiebreakKey = expectedKey
        try ctx.save()

        let fetchedFieldID = fieldA.fieldID
        let refetched = try #require(
            try ctx.fetch(FetchDescriptor<FieldValue>(
                predicate: #Predicate { $0.fieldDefinition?.fieldID == fetchedFieldID }
            )).first
        )
        #expect(refetched.tiebreakKey == expectedKey)
        // Specifically confirm the 3rd-field and createdDate segments (everything after the
        // first separator) actually made it through — this is exactly what NUL truncated.
        let segments = refetched.tiebreakKey.components(separatedBy: SortKeyEncoder.tiebreakSeparator)
        #expect(segments.count == 3, "expected [fieldB value, fieldC value, createdDate], got \(segments)")
    }
}
