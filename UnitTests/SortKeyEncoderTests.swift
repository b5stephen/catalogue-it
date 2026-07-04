//
//  SortKeyEncoderTests.swift
//  UnitTests
//

import Testing
import Foundation
@testable import catalogue_it

// MARK: - Sort Key Encoder Tests

/// Tests the primary `sortKey(for:)` encoding for every field type.
/// (Tiebreak key encoding is covered separately in SortKeyEncoderTiebreakTests.)
@MainActor
struct SortKeyEncoderTests {

    // MARK: - Helpers

    private func makeFieldValue(type: FieldType) -> FieldValue {
        FieldValue(fieldDefinition: nil, fieldType: type)
    }

    // MARK: - Text

    @Test("Text is lowercased for case-insensitive sorting")
    func textIsLowercased() {
        let fv = makeFieldValue(type: .text)
        fv.textValue = "SpitFire MkIX"
        #expect(SortKeyEncoder.sortKey(for: fv) == "spitfire mkix")
    }

    @Test("Nil and empty text encode as the missing-value sentinel")
    func missingTextUsesSentinel() {
        let nilValue = makeFieldValue(type: .text)
        #expect(SortKeyEncoder.sortKey(for: nilValue) == SortKeyEncoder.missingValueSentinel)

        let emptyValue = makeFieldValue(type: .text)
        emptyValue.textValue = ""
        #expect(SortKeyEncoder.sortKey(for: emptyValue) == SortKeyEncoder.missingValueSentinel)
    }

    @Test("The sentinel sorts after any real text value")
    func sentinelSortsAfterRealText() {
        let fv = makeFieldValue(type: .text)
        fv.textValue = "zzzz"
        #expect(SortKeyEncoder.sortKey(for: fv) < SortKeyEncoder.missingValueSentinel)
    }

    // MARK: - Number

    @Test("Zero encodes as the offset padded to fixed width")
    func zeroEncoding() {
        let fv = makeFieldValue(type: .number)
        fv.numberValue = 0
        #expect(SortKeyEncoder.sortKey(for: fv) == "01000000000000.000000")
    }

    @Test("Negative numbers encode below the offset")
    func negativeEncoding() {
        let fv = makeFieldValue(type: .number)
        fv.numberValue = -5
        #expect(SortKeyEncoder.sortKey(for: fv) == "00999999999995.000000")
    }

    @Test("Encoded number strings sort in the same order as their numeric values")
    func numberEncodingPreservesOrder() {
        let numbers: [Double] = [-1_000_000, -42.5, -1, -0.25, 0, 0.5, 1, 3.14, 999, 123_456_789]
        let keys = numbers.map { n -> String in
            let fv = makeFieldValue(type: .number)
            fv.numberValue = n
            return SortKeyEncoder.sortKey(for: fv)
        }
        #expect(keys == keys.sorted(), "Lexicographic key order must match numeric order")
    }

    @Test("Nil number encodes as the missing-value sentinel and sorts last")
    func missingNumberUsesSentinel() {
        let fv = makeFieldValue(type: .number)
        #expect(SortKeyEncoder.sortKey(for: fv) == SortKeyEncoder.missingValueSentinel)

        let big = makeFieldValue(type: .number)
        big.numberValue = 999_999_999
        #expect(SortKeyEncoder.sortKey(for: big) < SortKeyEncoder.missingValueSentinel)
    }

    // MARK: - Date

    @Test("Dates encode as ISO 8601 and preserve chronological order")
    func dateEncodingPreservesOrder() {
        let dates: [Date] = [
            Date(timeIntervalSince1970: 0),            // 1970
            Date(timeIntervalSince1970: 946_684_800),  // 2000
            Date(timeIntervalSince1970: 1_577_836_800) // 2020
        ]
        let keys = dates.map { d -> String in
            let fv = makeFieldValue(type: .date)
            fv.dateValue = d
            return SortKeyEncoder.sortKey(for: fv)
        }
        #expect(keys == keys.sorted(), "Lexicographic key order must match date order")
        #expect(keys[0].hasPrefix("1970-01-01"))
        #expect(keys[2].hasPrefix("2020-01-01"))
    }

    @Test("Nil date encodes as the missing-value sentinel")
    func missingDateUsesSentinel() {
        let fv = makeFieldValue(type: .date)
        #expect(SortKeyEncoder.sortKey(for: fv) == SortKeyEncoder.missingValueSentinel)
    }

    // MARK: - Boolean

    @Test("Booleans encode as 0 and 1, with nil as the sentinel")
    func booleanEncoding() {
        let falseValue = makeFieldValue(type: .boolean)
        falseValue.boolValue = false
        #expect(SortKeyEncoder.sortKey(for: falseValue) == "0")

        let trueValue = makeFieldValue(type: .boolean)
        trueValue.boolValue = true
        #expect(SortKeyEncoder.sortKey(for: trueValue) == "1")

        let nilValue = makeFieldValue(type: .boolean)
        #expect(SortKeyEncoder.sortKey(for: nilValue) == SortKeyEncoder.missingValueSentinel)
    }

    // MARK: - Option List

    @Test("Option list values encode like text: lowercased, sentinel when missing")
    func optionListEncoding() {
        let fv = makeFieldValue(type: .optionList)
        fv.textValue = "Mint Condition"
        #expect(SortKeyEncoder.sortKey(for: fv) == "mint condition")

        let empty = makeFieldValue(type: .optionList)
        empty.textValue = ""
        #expect(SortKeyEncoder.sortKey(for: empty) == SortKeyEncoder.missingValueSentinel)
    }
}
