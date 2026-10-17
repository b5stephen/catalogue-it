//
//  CatalogueIcon.swift
//  catalogue-it
//

import Foundation

// MARK: - Catalogue Icon

/// Emoji share `iconName` with SF Symbols, whose names are always ASCII, so no model change
/// was needed and export/import carry them as is.
nonisolated enum CatalogueIcon: Equatable {
    case symbol(String)
    case emoji(String)

    static let defaultSymbol = "square.grid.2x2"

    /// Empty falls back to the default symbol, so a value cleared by a future version still
    /// renders something.
    init(storedValue: String) {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self = .symbol(Self.defaultSymbol)
        } else if trimmed.allSatisfy(\.isASCII) {
            self = .symbol(trimmed)
        } else {
            // One grapheme cluster, so flags, skin tones and ZWJ sequences survive intact.
            self = .emoji(String(trimmed.prefix(1)))
        }
    }

    var storedValue: String {
        switch self {
        case .symbol(let value), .emoji(let value): value
        }
    }

    var isEmoji: Bool {
        if case .emoji = self { return true }
        return false
    }
}

// MARK: - Emoji Detection

extension Character {
    /// An emoji-presentation scalar (🎸), or a cluster led by an emoji-capable one (1️⃣, 🇬🇧).
    /// The scalar count keeps plainly typed digits and `#`, which are emoji-capable, out.
    nonisolated var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}
