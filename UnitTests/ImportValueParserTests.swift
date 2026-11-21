//
//  ImportValueParserTests.swift
//  UnitTests
//

import Testing
import Foundation
@testable import catalogue_it

struct ImportValueParserTests {

    private let london = TimeZone(identifier: "Europe/London")!

    private func parser(_ locale: String = "en_GB", order: ImportDateOrder? = nil) -> ImportValueParser {
        ImportValueParser(locale: Locale(identifier: locale), timeZone: london, dateOrder: order)
    }

    private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: Numbers

    @Test("Numbers in plain, grouped and currency forms", arguments: [
        ("1234.5", 1234.5), ("-12", -12), ("+3", 3), ("1,234.50", 1234.5), ("1.234,50", 1234.5),
        ("1 234,5", 1234.5), ("1'234.50", 1234.5), ("£12.50", 12.5), ("12,50 €", 12.5), ("(5)", -5),
        ("1,234,567", 1_234_567),
    ])
    func numbers(_ text: String, _ expected: Double) {
        #expect(parser().number(text)?.value == expected)
    }

    @Test("Text that only looks numeric is not a number", arguments: ["abc", "12a", "2020.01.01", "1,23,4", "1.2.3,4.5", "", "--1"])
    func notNumbers(_ text: String) {
        #expect(parser().number(text) == nil)
    }

    @Test("A lone separator before three digits follows the locale")
    func ambiguousSeparator() {
        #expect(parser("en_GB").number("1,234")?.value == 1234)
        #expect(parser("de_DE").number("1,234")?.value == 1.234)
        #expect(parser("en_GB").number("1.234")?.value == 1.234)
        #expect(parser("de_DE").number("1.234")?.value == 1234)
    }

    @Test("Decimal places and currency are recorded")
    func numberDetails() {
        let parsed = parser().number("$1,299.995")
        #expect(parsed?.fractionDigits == 3)
        #expect(parsed?.hadCurrencySymbol == true)
    }

    // MARK: Dates

    @Test("A day is noon that day")
    func isoDay() {
        #expect(parser().date("2026-03-01") == noon(2026, 3, 1))
        #expect(parser().date("2026/3/1") == noon(2026, 3, 1))
    }

    @Test("A timestamp keeps its instant")
    func timestamp() {
        #expect(parser().date("2026-03-01T08:30:00Z") == Date(timeIntervalSince1970: 1_772_353_800))
    }

    @Test("Numeric dates follow the chosen order")
    func dateOrder() {
        #expect(parser(order: .dayMonthYear).date("1/3/2026") == noon(2026, 3, 1))
        #expect(parser(order: .monthDayYear).date("1/3/2026") == noon(2026, 1, 3))
        #expect(parser(order: .dayMonthYear).date("31.12.99") == noon(1999, 12, 31))
    }

    @Test("Dates with month names", arguments: ["1 Mar 2026", "1 March 2026", "Mar 1, 2026", "March 1, 2026", "1-Mar-2026"])
    func textualDates(_ text: String) {
        #expect(parser().date(text) == noon(2026, 3, 1))
    }

    @Test("Days that don't exist are rejected", arguments: ["31/02/2026", "2026-13-01", "0/1/2026", "hello"])
    func invalidDates(_ text: String) {
        #expect(parser(order: .dayMonthYear).date(text) == nil)
    }

    @Test("The locale's numeric date order is the default")
    func preferredOrder() {
        #expect(ImportDateOrder.preferred(for: Locale(identifier: "en_GB")) == .dayMonthYear)
        #expect(ImportDateOrder.preferred(for: Locale(identifier: "en_US")) == .monthDayYear)
    }

    // MARK: Yes/No

    @Test("Yes/No words, ticks and the field's own labels")
    func bools() {
        let p = parser()
        #expect(p.bool("Yes") == true)
        #expect(p.bool("x") == true)
        #expect(p.bool("✓") == true)
        #expect(p.bool("FALSE") == false)
        #expect(p.bool("Built", trueLabel: "Built", falseLabel: "Unbuilt") == true)
        #expect(p.bool("unbuilt", trueLabel: "Built", falseLabel: "Unbuilt") == false)
        #expect(p.bool("maybe") == nil)
    }

    @Test("1 and 0 alone don't make a column Yes/No")
    func looksBoolean() {
        #expect(!parser().looksBoolean("1"))
        #expect(parser().looksBoolean("yes"))
    }
}
