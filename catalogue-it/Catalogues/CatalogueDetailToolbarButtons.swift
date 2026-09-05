//
//  CatalogueDetailToolbarButtons.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 16/03/2026.
//

import SwiftUI

// MARK: - Edit Catalogue Button

struct CatalogueEditButton: View {
    @Binding var showingEditCatalogue: Bool

    var body: some View {
        Button {
            showingEditCatalogue = true
        } label: {
            Label("Edit Catalogue", systemImage: "pencil")
        }
    }
}

// MARK: - Layout Toggle Button

struct LayoutToggleButton: View {
    @Binding var layout: ItemLayout

    var body: some View {
        Button {
            layout = layout.next
        } label: {
            Label(layout.nextLayoutLabel, systemImage: layout.nextLayoutIcon)
        }
    }
}

// MARK: - Add Item Button

struct AddItemButton: View {
    @Binding var showingAddItem: Bool

    var body: some View {
        Button {
            showingAddItem = true
        } label: {
            Label("Add Item", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}

// MARK: - Flag Filter Button

/// Surfaces the catalogue's `.flagFilter` fields as filter controls.
///
/// One flag gets a direct toggle button — the star/favourite pattern, one tap to filter.
/// Several collapse into a menu of independent toggles, since a row of toolbar icons
/// would crowd out everything else. Renders nothing when the catalogue defines no flags.
struct FlagFilterButton: View {
    let flagFields: [FieldDefinition]
    @Binding var activeFlagIDs: Set<UUID>

    private var isAnyActive: Bool { !activeFlagIDs.isEmpty }

    var body: some View {
        if flagFields.count == 1, let flag = flagFields.first {
            let isActive = activeFlagIDs.contains(flag.fieldID)
            Button {
                toggle(flag.fieldID)
            } label: {
                Label(flag.name, systemImage: flag.flagIconName ?? BooleanOptions.fallbackFilterIconName)
            }
            // The active state fills the chosen symbol and applies its tint. `.symbolVariant`
            // rather than a hardcoded ".fill" name, so a symbol with no filled counterpart
            // still renders instead of vanishing.
            .symbolVariant(isActive ? .fill : .none)
            .tint(isActive ? flag.flagColor : nil)
        } else if flagFields.count > 1 {
            Menu {
                ForEach(flagFields) { flag in
                    Toggle(isOn: Binding(
                        get: { activeFlagIDs.contains(flag.fieldID) },
                        set: { _ in toggle(flag.fieldID) }
                    )) {
                        Label(flag.name, systemImage: flag.flagIconName ?? BooleanOptions.fallbackFilterIconName)
                    }
                }
                if isAnyActive {
                    Divider()
                    Button("Clear Filters", systemImage: "xmark.circle") {
                        activeFlagIDs.removeAll()
                    }
                }
            } label: {
                Label(
                    "Filter",
                    systemImage: isAnyActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
        }
    }

    private func toggle(_ fieldID: UUID) {
        if activeFlagIDs.contains(fieldID) {
            activeFlagIDs.remove(fieldID)
        } else {
            activeFlagIDs.insert(fieldID)
        }
    }
}

// MARK: - Sort Menu Button

struct SortMenuButton: View {
    let catalogue: Catalogue
    @Binding var sortFieldKey: String
    @Binding var sortDirection: String

    private var sortedFields: [FieldDefinition] {
        catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
    }

    private var currentSortLabel: String {
        let field = ItemSortField(rawValue: sortFieldKey)
        switch field {
        case .dateAdded:
            return "Date Added"
        case .field(let uuid):
            return catalogue.fieldDefinitions.first { $0.fieldID == uuid }?.name ?? "Date Added"
        }
    }

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sortFieldKey) {
                Text("Date Added").tag(ItemSortField.dateAdded.rawValue)
                ForEach(sortedFields) { field in
                    Text(field.name).tag(ItemSortField.field(field.fieldID).rawValue)
                }
            }
            Picker("Direction", selection: $sortDirection) {
                Text("Ascending").tag(ItemSortDirection.ascending.rawValue)
                Text("Descending").tag(ItemSortDirection.descending.rawValue)
            }
        } label: {
            Label("Sort by", systemImage: "arrow.up.arrow.down")
            Text(currentSortLabel)
        }
    }
}
