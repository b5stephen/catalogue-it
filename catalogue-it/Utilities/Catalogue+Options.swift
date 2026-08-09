//
//  Catalogue+Options.swift
//  catalogue-it
//

import Foundation

// MARK: - Catalogue Options

/// Derives the item-list tab bar and flag filters from the catalogue's field definitions.
///
/// Nothing here is persisted — the configuration lives on `FieldDefinition.displayRole`,
/// and these accessors project it into the shapes the UI and predicates need.
extension Catalogue {

    /// The single field driving the tab bar, or `nil` when the catalogue has none.
    ///
    /// Validation permits at most one, but this defends against a store that somehow
    /// holds two (e.g. two devices each adding a status field before an iCloud merge)
    /// by deterministically preferring the lowest priority — every device picks the same one.
    var statusField: FieldDefinition? {
        fieldDefinitions
            .filter(\.isStatusField)
            .min { $0.priority < $1.priority }
    }

    /// Fields driving independent toggle filters, in the user's field order.
    var flagFields: [FieldDefinition] {
        fieldDefinitions
            .filter(\.isFlagField)
            .sorted { $0.priority < $1.priority }
    }

    /// The tabs to render, including the synthetic "All" tab when enabled.
    /// Empty when the catalogue has no status field — callers should hide the tab bar entirely.
    var statusTabDescriptors: [StatusTabDescriptor] {
        guard let field = statusField else { return [] }

        var tabs: [StatusTabDescriptor] = []
        if showAllTab {
            tabs.append(StatusTabDescriptor(tab: .all, label: String(localized: "All"), systemImage: "tray.2.fill"))
        }

        switch field.fieldType {
        case .optionList:
            // Defined order, not alphabetical — the user's ordering is the tab ordering.
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

    /// The tab a freshly opened catalogue should land on: "All" when shown, otherwise
    /// the status field's default value, otherwise the first tab.
    var defaultStatusTab: StatusTab {
        let tabs = statusTabDescriptors
        guard let first = tabs.first else { return .all }
        if showAllTab { return .all }
        return defaultStatusTabForNewItems ?? first.tab
    }

    /// The tab matching the status field's configured default value — the state a new
    /// item starts in. `nil` when there's no status field or no default is configured.
    var defaultStatusTabForNewItems: StatusTab? {
        guard let field = statusField else { return nil }
        switch field.fieldType {
        case .optionList:
            let opts = field.optionListOptions
            if let defaultValue = opts?.defaultValue, opts?.options.contains(defaultValue) == true {
                return .option(defaultValue)
            }
            // Spec: new items default to the first option when no default is set.
            return opts?.options.first.map { StatusTab.option($0) }
        case .boolean:
            return (field.booleanOptions?.defaultValue ?? false) ? .boolTrue : .boolFalse
        case .text, .number, .date:
            return nil
        }
    }

    /// Clamps a selection to one the catalogue still offers. A tab can disappear
    /// underneath the user when the status field is edited on another device.
    func resolvedStatusTab(_ tab: StatusTab) -> StatusTab {
        let tabs = statusTabDescriptors
        guard !tabs.isEmpty else { return .all }
        return tabs.contains { $0.tab == tab } ? tab : (tabs.first?.tab ?? .all)
    }
}
