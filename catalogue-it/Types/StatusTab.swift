//
//  StatusTab.swift
//  catalogue-it
//

import Foundation

// MARK: - Status Tab

/// `storedValue` must match `ItemFacetBuilder`'s encoding of `CatalogueItem.statusValue`.
nonisolated enum StatusTab: Hashable, Codable {
    case all
    case option(String)
    case boolTrue
    case boolFalse

    var storedValue: String? {
        switch self {
        case .all:            nil
        case .option(let v):  v
        case .boolTrue:       ItemFacetBuilder.boolTrueToken
        case .boolFalse:      ItemFacetBuilder.boolFalseToken
        }
    }
}

// MARK: - Status Tab Descriptor

nonisolated struct StatusTabDescriptor: Identifiable, Hashable {
    let tab: StatusTab
    let label: String
    let systemImage: String

    var id: StatusTab { tab }
}

nonisolated extension StatusTabDescriptor {
    /// Shared by the item list and the catalogue form's preview, so the preview can't drift.
    /// Empty for a field type that can't drive tabs.
    static func tabs(
        fieldType: FieldType,
        options: [String],
        booleanLabels: (trueLabel: String, falseLabel: String),
        showAllTab: Bool
    ) -> [StatusTabDescriptor] {
        var tabs: [StatusTabDescriptor] = []
        if showAllTab {
            tabs.append(StatusTabDescriptor(tab: .all, label: String(localized: "All"), systemImage: "tray.2.fill"))
        }

        switch fieldType {
        case .optionList:
            // The user's option order is the tab order.
            tabs += options.map {
                StatusTabDescriptor(tab: .option($0), label: $0, systemImage: "circle.fill")
            }
        case .boolean:
            tabs.append(StatusTabDescriptor(tab: .boolTrue, label: booleanLabels.trueLabel, systemImage: "checkmark.circle.fill"))
            tabs.append(StatusTabDescriptor(tab: .boolFalse, label: booleanLabels.falseLabel, systemImage: "circle"))
        case .text, .number, .date:
            break
        }
        return tabs
    }
}
