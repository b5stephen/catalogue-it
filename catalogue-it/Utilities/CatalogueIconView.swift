//
//  CatalogueIconView.swift
//  catalogue-it
//

import SwiftUI
import ImageIO
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Catalogue Icon View

/// `color` applies to symbols only: emoji, Genmoji and photos carry their own. A photo fills
/// the space it is offered, clipped to `tileCornerRadius` so it takes the tile's corners.
struct CatalogueIconView: View {
    let icon: CatalogueIcon
    let color: Color
    let size: CGFloat
    var tileCornerRadius: CGFloat = 0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        switch icon {
        case .symbol(let name):
            symbol(name)
        case .emoji(let emoji):
            emojiText(emoji)
        case .photo(let data):
            if let image = CatalogueIconImages.photo(from: data) {
                Color.clear
                    .overlay {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(.rect(cornerRadius: tileCornerRadius, style: .continuous))
            } else {
                symbol(CatalogueIcon.defaultSymbol)
            }
        case .genmoji(let data):
            // The emoji's box, so a Genmoji and an emoji in neighbouring rows match.
            let side = emojiSize
            if let glyph = CatalogueIconImages.genmoji(from: data, pointSize: side, scale: displayScale) {
                Image(decorative: glyph.image, scale: displayScale)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .accessibilityLabel(glyph.description)
            } else {
                symbol(CatalogueIcon.defaultSymbol)
            }
        }
    }

    /// Larger: SF Symbols fill their box, while emoji sit inside theirs.
    private var emojiSize: CGFloat { size * 1.15 }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size))
            .foregroundStyle(color)
    }

    private func emojiText(_ emoji: String) -> some View {
        Text(emoji)
            .font(.system(size: emojiSize))
    }
}

// MARK: - Catalogue Icon Images

/// Decoded icon images, keyed by content: icons render in every sidebar row and card, so each
/// is decoded once rather than per `body`. Keying by content also means an icon merged in from
/// another device misses the cache instead of showing the old image.
enum CatalogueIconImages {
    private final class Box<Value> {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    struct Glyph {
        let image: CGImage
        let description: String
    }

    // `NSData` keys hash a prefix of the bytes and compare the rest only on a collision.
    private static let photos = NSCache<NSData, Box<CGImage>>()
    private static let glyphs = NSCache<NSString, Box<Glyph>>()

    static func photo(from data: Data) -> CGImage? {
        let key = data as NSData
        if let cached = photos.object(forKey: key) { return cached.value }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        photos.setObject(Box(image), forKey: key)
        return image
    }

    static func genmoji(from data: Data, pointSize: CGFloat, scale: CGFloat) -> Glyph? {
        // The initialiser can't fail, so anything that isn't an image is turned away first.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let glyph = NSAdaptiveImageGlyph(imageContent: data)
        let key = "\(glyph.contentIdentifier)@\(pointSize)x\(scale)" as NSString
        if let cached = glyphs.object(forKey: key) { return cached.value }

        var offset = CGPoint.zero
        var imageSize = CGSize.zero
        let proposed = CGSize(width: pointSize, height: pointSize)
        guard let image = glyph.image(
            forProposedSize: proposed,
            scaleFactor: scale,
            imageOffset: &offset,
            imageSize: &imageSize
        ) else { return nil }

        let rendered = Glyph(image: image, description: glyph.contentDescription)
        glyphs.setObject(Box(rendered), forKey: key)
        return rendered
    }
}
