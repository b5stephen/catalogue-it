//
//  ExportColumn.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Export Format

enum ExportFormat: CaseIterable, Identifiable {
    case message
    case card
    case spreadsheet

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .message: "Message"
        case .card: "Card"
        case .spreadsheet: "Spreadsheet"
        }
    }

    /// Fields in `sortedFieldDefinitions` order, then the Item info extras.
    func columns(for catalogue: Catalogue) -> [ExportColumn] {
        var columns = catalogue.sortedFieldDefinitions.map { ExportColumn.field($0.fieldID) }
        columns.append(.notes)
        if self == .spreadsheet {
            columns.append(contentsOf: [.dateAdded, .photoCount])
        }
        return columns
    }

    /// The first field names the item in a message or card, so it can't be left out. A
    /// spreadsheet has no title.
    func lockedColumn(for catalogue: Catalogue) -> ExportColumn? {
        guard self != .spreadsheet, let first = catalogue.sortedFieldDefinitions.first else { return nil }
        return .field(first.fieldID)
    }
}

// MARK: - Export Column

enum ExportColumn: Hashable {
    case field(UUID)
    case notes
    case dateAdded
    case photoCount

    func title(in catalogue: Catalogue) -> String {
        switch self {
        case .field(let id):
            catalogue.fieldDefinitions.first { $0.fieldID == id }?.name ?? ""
        case .notes: String(localized: "Notes")
        case .dateAdded: String(localized: "Date Added")
        case .photoCount: String(localized: "Photo Count")
        }
    }
}
