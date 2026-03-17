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
    case table = "table"

    var next: ItemLayout {
        switch self {
        case .grid:  .list
        case .list:  .table
        case .table: .grid
        }
    }

    var nextLayoutIcon: String {
        switch self {
        case .grid:  "list.bullet"
        case .list:  "tablecells"
        case .table: "square.grid.2x2"
        }
    }

    var nextLayoutLabel: String {
        switch self {
        case .grid:  "Switch to List"
        case .list:  "Switch to Table"
        case .table: "Switch to Grid"
        }
    }
}
