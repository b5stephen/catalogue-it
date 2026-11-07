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

// MARK: - Flag Filter Toggles

/// One toggle per flag, for placing inside a menu, where a toggle shows its state as a checkmark.
struct FlagFilterToggles: View {
    let flagFields: [FieldDefinition]
    @Binding var activeFlagIDs: Set<UUID>

    var body: some View {
        ForEach(flagFields) { flag in
            Toggle(isOn: Binding(
                get: { activeFlagIDs.contains(flag.fieldID) },
                set: { isOn in
                    if isOn { activeFlagIDs.insert(flag.fieldID) } else { activeFlagIDs.remove(flag.fieldID) }
                }
            )) {
                Label(flag.name, systemImage: flag.flagIconName ?? BooleanOptions.fallbackFilterIconName)
            }
        }
    }
}

// MARK: - Flag Filter Button

/// For a bar with room for it: one flag gets a direct toggle; several collapse into a menu of
/// toggles rather than crowding the bar. Renders nothing without flags.
struct FlagFilterButton: View {
    let flagFields: [FieldDefinition]
    @Binding var activeFlagIDs: Set<UUID>

    private var isAnyActive: Bool { !activeFlagIDs.isEmpty }

    var body: some View {
        if flagFields.count == 1, let flag = flagFields.first {
            let isActive = activeFlagIDs.contains(flag.fieldID)
            Button {
                if isActive { activeFlagIDs.remove(flag.fieldID) } else { activeFlagIDs.insert(flag.fieldID) }
            } label: {
                Label(flag.name, systemImage: flag.flagIconName ?? BooleanOptions.fallbackFilterIconName)
            }
            // `.symbolVariant` rather than a ".fill" name, so a symbol with no filled form still renders.
            .symbolVariant(isActive ? .fill : .none)
            .tint(isActive ? flag.flagColor : nil)
        } else if flagFields.count > 1 {
            Menu {
                FlagFilterToggles(flagFields: flagFields, activeFlagIDs: $activeFlagIDs)
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
}

// MARK: - Sort Menu Button

struct SortMenuButton: View {
    let catalogue: Catalogue
    @Binding var sortFieldKey: String
    @Binding var sortDirection: String

    private var sortedFields: [FieldDefinition] {
        catalogue.sortedFieldDefinitions
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
