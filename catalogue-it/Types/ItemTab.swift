//
//  ItemTab.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import Foundation

// MARK: - Item Tab

enum ItemTab: String, CaseIterable {
    case all = "All"
    case owned = "Owned"
    case wishlist = "Wishlist"

    var systemImage: String {
        switch self {
        case .all: "tray.2.fill"
        case .owned: "checkmark.circle.fill"
        case .wishlist: "heart.fill"
        }
    }
}
