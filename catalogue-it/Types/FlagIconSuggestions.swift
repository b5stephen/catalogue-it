//
//  FlagIconSuggestions.swift
//  catalogue-it
//

import Foundation

// MARK: - Flag Icon Suggestions

/// SF Symbols ranked for a Yes/No field by what its name says. Keywords are English words, so a
/// name in another language matches nothing and gets the fallback order.
nonisolated enum FlagIconSuggestions {

    struct Result: Equatable {
        let symbols: [String]
        /// `false` when `symbols` is the fallback order alone.
        let matched: Bool
    }

    /// Listed in priority order: earlier rules' symbols rank first.
    private static let rules: [(keywords: Set<String>, symbols: [String])] = [
        (["built", "build", "assembled", "made", "finished", "complete", "painted"],
         ["hammer.fill", "checkmark.circle.fill"]),
        (["favourite", "favorite", "love", "like", "best"], ["heart.fill", "star.fill"]),
        (["wish", "want", "wanted"], ["star.fill", "heart.fill"]),
        (["owned", "own", "have", "got", "collected"], ["checkmark.circle.fill", "shippingbox.fill"]),
        (["sold", "sale", "sell", "trade", "swap"], ["tag.fill"]),
        (["shipped", "arrived", "delivered", "received", "ordered", "boxed"], ["shippingbox.fill"]),
        (["read", "watched", "played", "seen", "done", "visited"], ["checkmark.circle.fill"]),
        (["important", "priority", "flag", "urgent"], ["flag.fill"])
    ]

    private static let fallback = [
        "star.fill", "checkmark.circle.fill", "heart.fill", "flag.fill",
        "tag.fill", "shippingbox.fill", "hammer.fill"
    ]

    static func suggestions(for name: String, limit: Int = 6) -> Result {
        let words = Set(name.lowercased().split { !$0.isLetter }.map(String.init))

        var symbols: [String] = []
        var matched = false
        for rule in rules where !rule.keywords.isDisjoint(with: words) {
            matched = true
            for symbol in rule.symbols where !symbols.contains(symbol) {
                symbols.append(symbol)
            }
        }
        for symbol in fallback where !symbols.contains(symbol) {
            symbols.append(symbol)
        }
        return Result(symbols: Array(symbols.prefix(max(limit, 0))), matched: matched)
    }

    static func ranked(for name: String, limit: Int = 6) -> [String] {
        suggestions(for: name, limit: limit).symbols
    }
}
