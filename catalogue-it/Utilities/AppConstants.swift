//
//  AppConstants.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 16/03/2026.
//

import SwiftUI

// MARK: - App Design Constants

/// Declared `nonisolated` to opt out of the module's default `@MainActor` isolation,
/// so these plain constants are usable from any actor context (e.g. as default
/// values for SwiftData model properties, which are themselves `nonisolated`).
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
    /// Metrics for the catalogue cards on the Catalogues screen. Catalogues are the app's
    /// entry point and there are few of them, so the cards are deliberately roomier than a
    /// standard list row.
    enum CatalogueCard {
        static let iconTile: CGFloat = 52
        static let contentPadding: CGFloat = 14
        static let horizontalInset: CGFloat = 16
        static let rowSpacing: CGFloat = 12
        /// Nested-radius rule: inner radius = outer radius − padding (see the card-design skill).
        static let iconTileCornerRadius: CGFloat = CornerRadius.card - contentPadding
    }
    /// Metrics for the item cards in the list layout. Same inset as the catalogue cards so
    /// the two screens line up; a tighter gap, because there are many more of these.
    enum ItemCard {
        static let horizontalInset: CGFloat = 16
        static let rowSpacing: CGFloat = 8
        /// Uniform on all sides: the thumbnail's corners can only sit concentric with the
        /// card's if it is inset the same amount horizontally and vertically.
        static let contentPadding: CGFloat = 10
        /// Nested-radius rule: inner radius = outer radius − padding. Anything larger and the
        /// gap between the two curves widens at the corner; anything smaller and it pinches.
        static let thumbnailCornerRadius: CGFloat = CornerRadius.card - contentPadding
    }
    enum GridCardSize {
        static let min: CGFloat = 100
        static let max: CGFloat = 320
        static let defaultSize: CGFloat = 160
    }
}
