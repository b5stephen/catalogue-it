//
//  AppConstants.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 16/03/2026.
//

import SwiftUI

// MARK: - App Design Constants

/// `nonisolated` so the constants can be SwiftData property defaults.
nonisolated enum AppConstants {
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let card: CGFloat = 18
    }
    enum ThumbnailSize {
        static let list: CGFloat = 56
        static let photoPicker: CGFloat = 90
    }
    enum PhotoHeight {
        static let detail: CGFloat = 280
    }
    /// Roomier than a standard row: catalogues are the entry point, and few.
    enum CatalogueCard {
        static let iconTile: CGFloat = 52
        static let contentPadding: CGFloat = 14
        static let horizontalInset: CGFloat = 16
        static let rowSpacing: CGFloat = 12
        /// Inner radius = outer − padding (see the card-design skill).
        static let iconTileCornerRadius: CGFloat = CornerRadius.card - contentPadding
    }
    /// The Add/Edit Catalogue form's header card.
    enum CatalogueHeader {
        static let iconTile: CGFloat = 76
        static let iconTileCornerRadius: CGFloat = 22
        static let swatch: CGFloat = 30
        static let swatchTapSize: CGFloat = 44
        /// Uniform, or the name field's corners can't be concentric with the card's.
        static let contentPadding: CGFloat = 12
        /// Approximates the Form section card's corner radius, which the system doesn't expose.
        static let sectionCornerRadius: CGFloat = 26
        /// Inner radius = outer − padding (see the card-design skill).
        static let nameFieldCornerRadius: CGFloat = sectionCornerRadius - contentPadding
    }
    /// The catalogue cards' inset, so the screens line up; a tighter gap, as there are more.
    enum ItemCard {
        static let horizontalInset: CGFloat = 16
        static let rowSpacing: CGFloat = 8
        /// Uniform, or the thumbnail's corners can't be concentric with the card's.
        static let contentPadding: CGFloat = 10
        /// Inner radius = outer − padding; otherwise the gap between the curves widens or pinches
        /// at the corner.
        static let thumbnailCornerRadius: CGFloat = CornerRadius.card - contentPadding
    }
    enum GridCardSize {
        static let min: CGFloat = 100
        static let max: CGFloat = 320
        static let defaultSize: CGFloat = 160
    }
}
