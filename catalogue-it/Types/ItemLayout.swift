//
//  ItemLayout.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 17/03/2026.
//

import Foundation

// MARK: - Item Layout

enum ItemLayout: String, CaseIterable, Identifiable {
    case grid  = "grid"
    case list  = "list"

    var id: Self { self }

    var next: ItemLayout {
        switch self {
        case .grid: .list
        case .list: .grid
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .grid: "Gallery"
        case .list: "List"
        }
    }

    var icon: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }

    var nextLayoutIcon: String { next.icon }

    var nextLayoutLabel: String {
        switch self {
        case .grid: "View as List"
        case .list: "View as Gallery"
        }
    }
}
