//
//  CatalogueIconView.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Catalogue Icon View

/// `color` applies to symbols only: emoji carry their own.
struct CatalogueIconView: View {
    let iconName: String
    let color: Color
    let size: CGFloat

    var body: some View {
        switch CatalogueIcon(storedValue: iconName) {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundStyle(color)
        case .emoji(let emoji):
            // Larger: SF Symbols fill their box, while emoji sit inside theirs.
            Text(emoji)
                .font(.system(size: size * 1.15))
        }
    }
}
