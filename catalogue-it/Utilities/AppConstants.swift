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
    /// Metrics for the catalogue cards on the My Catalogues screen. Catalogues are the app's
    /// entry point and there are few of them, so the cards are deliberately roomier than a
    /// standard list row.
    enum CatalogueCard {
        static let iconTile: CGFloat = 52
        static let contentPadding: CGFloat = 14
        static let horizontalInset: CGFloat = 16
        static let rowSpacing: CGFloat = 12
        /// A card has room for a short chip row before it wraps; populated statuses win the slots.
        static let maxStatusChips: Int = 3
    }
    enum GridCardSize {
        static let min: CGFloat = 100
        static let max: CGFloat = 320
        static let defaultSize: CGFloat = 160
    }
}
