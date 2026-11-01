//
//  CatalogueIcon.swift
//  catalogue-it
//

import Foundation

// MARK: - Catalogue Icon

/// Symbols and emoji share `iconName` (SF Symbol names are always ASCII); photos and Genmoji
/// live in `iconImageData`, tagged by `iconImageKind`.
nonisolated enum CatalogueIcon: Equatable {
    case symbol(String)
    case emoji(String)
    /// A square JPEG, at most `photoPixelSize` on a side.
    case photo(Data)
    /// An `NSAdaptiveImageGlyph`'s `imageContent`.
    case genmoji(Data)

    static let defaultSymbol = "square.grid.2x2"
    static let photoPixelSize = 512

    /// The raw values of `Catalogue.iconImageKind`.
    enum ImageKind: String {
        case photo
        case genmoji
    }

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

    /// A kind this build doesn't know (written by a newer one) falls back to `iconName`.
    init(iconName: String, imageData: Data?, imageKind: String?) {
        switch (imageData, imageKind.flatMap(ImageKind.init(rawValue:))) {
        case (let data?, .photo): self = .photo(data)
        case (let data?, .genmoji): self = .genmoji(data)
        default: self = CatalogueIcon(storedValue: iconName)
        }
    }

    /// Nil for image icons, which keep the catalogue's previous `iconName` as their fallback.
    var iconName: String? {
        switch self {
        case .symbol(let value), .emoji(let value): value
        case .photo, .genmoji: nil
        }
    }

    var imageData: Data? {
        switch self {
        case .photo(let data), .genmoji(let data): data
        case .symbol, .emoji: nil
        }
    }

    var imageKind: ImageKind? {
        switch self {
        case .photo: .photo
        case .genmoji: .genmoji
        case .symbol, .emoji: nil
        }
    }

    var isEmoji: Bool {
        switch self {
        case .emoji, .genmoji: true
        case .symbol, .photo: false
        }
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
