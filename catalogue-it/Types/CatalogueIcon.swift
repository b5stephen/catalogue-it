//
//  CatalogueIcon.swift
//  catalogue-it
//

import Foundation

// MARK: - Catalogue Icon

/// How a catalogue's stored `iconName` should be drawn.
///
/// Emoji share the existing `iconName` property rather than getting one of their own. SF Symbol
/// names are always ASCII, so the two can never be confused, and reusing the property keeps this
/// a presentation choice rather than a model change — no schema version, no CloudKit deploy. It
/// also means emoji travel through export/import for free, since `CatalogueTransferData` already
/// carries `iconName` verbatim.
nonisolated enum CatalogueIcon: Equatable {
    case symbol(String)
    case emoji(String)

    static let defaultSymbol = "square.grid.2x2"

    /// Classifies a stored icon value. Anything non-ASCII is an emoji; an empty value falls back
    /// to the default symbol, so a catalogue synced from a future version that cleared the field
    /// still renders something.
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
    /// Whether this character renders as emoji.
    ///
    /// Two cases: a single scalar that defaults to emoji presentation (🎸), and a multi-scalar
    /// cluster whose first scalar is emoji-capable (1️⃣, 🇬🇧, 👨‍👩‍👧). The second test needs the
    /// scalar count, because ASCII digits and `#` are emoji-capable on their own but should not
    /// count as emoji when typed plainly.
    /// `nonisolated` so it is callable from any context — the module defaults to `@MainActor`,
    /// and this is a pure test on the character's scalars.
    nonisolated var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}
