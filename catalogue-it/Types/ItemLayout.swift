//
//  ItemLayout.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 17/03/2026.
//

// MARK: - Item Layout

enum ItemLayout: String, CaseIterable {
    case grid  = "grid"
    case list  = "list"

    var next: ItemLayout {
        switch self {
        case .grid: .list
        case .list: .grid
        }
    }

    var nextLayoutIcon: String {
        switch self {
        case .grid: "list.bullet"
        case .list: "square.grid.2x2"
        }
    }

    var nextLayoutLabel: String {
        switch self {
        case .grid: "View as List"
        case .list: "View as Gallery"
        }
    }
}
