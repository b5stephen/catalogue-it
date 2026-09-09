//
//  CatalogueIconView.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Catalogue Icon View

/// Draws a catalogue's icon, whichever kind it is: an SF Symbol tinted with the catalogue's
/// colour, or the emoji the user picked in its place.
///
/// Emoji carry their own colour, so `color` applies to symbols only.
struct CatalogueIconView: View {
    let iconName: String
    let color: Color
    /// Point size of the glyph.
    let size: CGFloat

    var body: some View {
        switch CatalogueIcon(storedValue: iconName) {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundStyle(color)
        case .emoji(let emoji):
            // Nudged up: an emoji set at a symbol's point size reads smaller, because SF Symbols
            // are drawn to fill their box while emoji sit inside theirs.
            Text(emoji)
                .font(.system(size: size * 1.15))
        }
    }
}
