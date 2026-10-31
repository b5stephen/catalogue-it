//
//  Catalogue+Options.swift
//  catalogue-it
//

import Foundation

// MARK: - Catalogue Options

/// Projections of `FieldDefinition.displayRole`; nothing here is persisted.
extension Catalogue {

    /// Two devices can each add a status field before a merge, so the lowest priority wins,
    /// the same on every device.
    var statusField: FieldDefinition? {
        fieldDefinitions
            .filter(\.isStatusField)
            .min(by: FieldDefinition.isOrderedBefore)
    }

    var flagFields: [FieldDefinition] {
        fieldDefinitions
            .filter(\.isFlagField)
            .sorted(by: FieldDefinition.isOrderedBefore)
    }

    var iconBadgeFields: [FieldDefinition] {
        fieldDefinitions
            .filter(\.showsIconBadge)
            .sorted(by: FieldDefinition.isOrderedBefore)
    }

    /// Empty without a status field, where the tab bar should be hidden.
    var statusTabDescriptors: [StatusTabDescriptor] {
        guard let field = statusField else { return [] }
        return StatusTabDescriptor.tabs(
            fieldType: field.fieldType,
            options: field.optionListOptions?.options ?? [],
            booleanLabels: field.statusTabLabels,
            showAllTab: showAllTab
        )
    }

    /// "All" when shown, else the status field's default, else the first tab.
    var defaultStatusTab: StatusTab {
        let tabs = statusTabDescriptors
        guard let first = tabs.first else { return .all }
        if showAllTab { return .all }
        return defaultStatusTabForNewItems ?? first.tab
    }

    /// The state a new item starts in.
    var defaultStatusTabForNewItems: StatusTab? {
        guard let field = statusField else { return nil }
        switch field.fieldType {
        case .optionList:
            let opts = field.optionListOptions
            if let defaultValue = opts?.defaultValue, opts?.options.contains(defaultValue) == true {
                return .option(defaultValue)
            }
            return opts?.options.first.map { StatusTab.option($0) }
        case .boolean:
            return (field.booleanOptions?.defaultValue ?? false) ? .boolTrue : .boolFalse
        case .text, .number, .date:
            return nil
        }
    }

    /// A tab can disappear when the status field is edited on another device.
    func resolvedStatusTab(_ tab: StatusTab) -> StatusTab {
        let tabs = statusTabDescriptors
        guard !tabs.isEmpty else { return .all }
        return tabs.contains { $0.tab == tab } ? tab : (tabs.first?.tab ?? .all)
    }
}
