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

    /// Past this many items a message is too long to be of use.
    static let messageItemLimit = 50

    var title: LocalizedStringKey {
        switch self {
        case .message: "Message"
        case .card: "Card"
        case .spreadsheet: "Spreadsheet"
        }
    }

    /// Select mode opens on Message up to this many items.
    static let messageDefaultLimit = 20

    static func defaultFormat(forItemCount count: Int) -> ExportFormat {
        count <= messageDefaultLimit ? .message : .spreadsheet
    }

    /// Card is for one item, Message for a short list.
    static func available(forItemCount count: Int) -> [ExportFormat] {
        switch count {
        case 1: allCases
        case 2...messageItemLimit: [.message, .spreadsheet]
        default: [.spreadsheet]
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

nonisolated enum ExportColumn: Hashable, Sendable {
    case field(UUID)
    case notes
    case dateAdded
    case photoCount

    /// Notes, Date Added and Photo Count, listed apart from the catalogue's own fields.
    var isItemInfo: Bool {
        if case .field = self { false } else { true }
    }

    /// `nil` for a field, whose title is its definition's name.
    var itemInfoTitle: String? {
        switch self {
        case .field: nil
        case .notes: String(localized: "Notes")
        case .dateAdded: String(localized: "Date Added")
        case .photoCount: String(localized: "Photo Count")
        }
    }

    func title(in catalogue: Catalogue) -> String {
        if case .field(let id) = self {
            return catalogue.fieldDefinitions.first { $0.fieldID == id }?.name ?? ""
        }
        return itemInfoTitle ?? ""
    }
}
