//
//  ItemTab.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import Foundation

// MARK: - Item Tab

enum ItemTab: String, CaseIterable {
    case owned = "Owned"
    case wishlist = "Wishlist"

    var systemImage: String {
        switch self {
        case .owned: "checkmark.circle.fill"
        case .wishlist: "heart.fill"
        }
    }
}
