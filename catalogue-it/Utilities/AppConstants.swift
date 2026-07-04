//
//  AppConstants.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 16/03/2026.
//

import SwiftUI

// MARK: - App Design Constants

enum AppConstants {
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
    }
    enum ThumbnailSize {
        static let list: CGFloat = 56
        static let photoPicker: CGFloat = 90
    }
    enum PhotoHeight {
        static let detail: CGFloat = 280
    }
    enum GridCardSize {
        static let min: CGFloat = 100
        static let max: CGFloat = 320
        static let defaultSize: CGFloat = 160
    }
}
