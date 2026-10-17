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

    /// Empty without a status field, where the tab bar should be hidden.
    var statusTabDescriptors: [StatusTabDescriptor] {
        guard let field = statusField else { return [] }

        var tabs: [StatusTabDescriptor] = []
        if showAllTab {
            tabs.append(StatusTabDescriptor(tab: .all, label: String(localized: "All"), systemImage: "tray.2.fill"))
        }

        switch field.fieldType {
        case .optionList:
            // The user's option order is the tab order.
            let options = field.optionListOptions?.options ?? []
            tabs += options.map {
                StatusTabDescriptor(tab: .option($0), label: $0, systemImage: "circle.fill")
            }
        case .boolean:
            let labels = field.statusTabLabels
            tabs.append(StatusTabDescriptor(tab: .boolTrue, label: labels.trueLabel, systemImage: "checkmark.circle.fill"))
            tabs.append(StatusTabDescriptor(tab: .boolFalse, label: labels.falseLabel, systemImage: "circle"))
        case .text, .number, .date:
            break
        }
        return tabs
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
