//
//  FlagIconSuggestionsTests.swift
//  UnitTests
//

import Testing
@testable import catalogue_it

// MARK: - Flag Icon Suggestions Tests

struct FlagIconSuggestionsTests {

    @Test("A build-related name leads with the hammer")
    func builtLeadsWithHammer() {
        let result = FlagIconSuggestions.suggestions(for: "Built")
        #expect(result.symbols.first == "hammer.fill")
        #expect(result.matched)
    }

    @Test("A favourite-related name leads with the heart")
    func favouriteLeadsWithHeart() {
        #expect(FlagIconSuggestions.ranked(for: "Favourite").first == "heart.fill")
        #expect(FlagIconSuggestions.ranked(for: "Favorite").first == "heart.fill")
    }

    @Test("Keywords match whole words anywhere in the name")
    func matchesWordsInPhrases() {
        #expect(FlagIconSuggestions.ranked(for: "For Sale").first == "tag.fill")
        #expect(FlagIconSuggestions.ranked(for: "built-and-painted").first == "hammer.fill")
        #expect(FlagIconSuggestions.suggestions(for: "Unbuilt").matched == false)
    }

    @Test("Several matching rules merge in rule order without duplicates")
    func multiKeywordMergesWithoutDuplicates() {
        let symbols = FlagIconSuggestions.ranked(for: "Owned Favourite Built")
        #expect(symbols.prefix(4) == ["hammer.fill", "checkmark.circle.fill", "heart.fill", "star.fill"])
        #expect(Set(symbols).count == symbols.count)
    }

    @Test("An unmatched name gets the fallback order")
    func unmatchedUsesFallback() {
        let result = FlagIconSuggestions.suggestions(for: "Zebra")
        #expect(!result.matched)
        #expect(result.symbols == [
            "star.fill", "checkmark.circle.fill", "heart.fill", "flag.fill", "tag.fill", "shippingbox.fill"
        ])
        #expect(FlagIconSuggestions.suggestions(for: "").matched == false)
    }

    @Test("Matches are topped up from the fallback order")
    func matchesFillFromFallback() {
        let symbols = FlagIconSuggestions.ranked(for: "Sold")
        #expect(symbols == [
            "tag.fill", "star.fill", "checkmark.circle.fill", "heart.fill", "flag.fill", "shippingbox.fill"
        ])
    }

    @Test("The limit caps the result")
    func limitIsRespected() {
        #expect(FlagIconSuggestions.ranked(for: "Built", limit: 3).count == 3)
        #expect(FlagIconSuggestions.ranked(for: "Built", limit: 0).isEmpty)
        #expect(FlagIconSuggestions.ranked(for: "Built", limit: 20).count == 7)
    }
}
