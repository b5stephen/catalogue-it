//
//  Catalogue.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData


// MARK: - Catalogue

@Model
final class Catalogue {
    // Every stored property below carries a default value: CloudKit rejects
    // non-optional attributes that have none, and the container fails to build.
    var name: String = ""
    var createdDate: Date = Date.now
    var iconName: String = "square.grid.2x2" // SF Symbol name
    var colorHex: String = "#007AFF"
    var priority: Int = 0

    var sortFieldKey: String = ItemSortField.dateAdded.rawValue
    var sortDirection: String = ItemSortDirection.ascending.rawValue

    /// Hides the catalogue while `BackgroundDeletionActor` tears it down. Persisted and synced
    /// so an interrupted deletion resumes on next launch.
    var pendingDeletion: Bool = false

    /// The "All" tab ahead of a `.statusTabs` field's own. Opt-in: a status field usually
    /// means the user wants to work in one state at a time.
    var showAllTab: Bool = false

    /// Read through `layoutOptions`. Nil means every option is at its default.
    var layoutOptionsData: Data?

    var itemLayoutRaw_mac: String = ItemLayout.list.rawValue
    var itemLayoutRaw_ios: String = ItemLayout.list.rawValue
    var gridCardSize_mac: Double = Double(AppConstants.GridCardSize.defaultSize)
    var gridCardSize_ios: Double = Double(AppConstants.GridCardSize.defaultSize)

    // Optional for CloudKit; use the accessors below. Only key paths handed to SwiftData
    // (predicates, prefetching) should name these directly.
    @Relationship(deleteRule: .cascade, inverse: \FieldDefinition.catalogue)
    var storedFieldDefinitions: [FieldDefinition]? = []

    @Relationship(deleteRule: .cascade, inverse: \CatalogueItem.catalogue)
    var storedItems: [CatalogueItem]? = []

    init(name: String, iconName: String = "square.grid.2x2", colorHex: String = "#007AFF", priority: Int = 0) {
        self.name = name
        self.createdDate = Date.now
        self.iconName = iconName
        self.colorHex = colorHex
        self.priority = priority
    }
}

// MARK: - Layout Options

extension Catalogue {
    var layoutOptions: CatalogueLayoutOptions {
        get {
            guard let layoutOptionsData,
                  let options = try? JSONDecoder().decode(CatalogueLayoutOptions.self, from: layoutOptionsData) else {
                return CatalogueLayoutOptions()
            }
            return options
        }
        set {
            // An equal value rewritten still exports, and can bounce between devices.
            guard newValue != layoutOptions else { return }
            layoutOptionsData = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Per-Platform Preferences

extension Catalogue {
    /// Stored per platform, so a synced catalogue can use a different layout on Mac.
    var itemLayout: ItemLayout {
        get {
#if os(macOS)
            ItemLayout(rawValue: itemLayoutRaw_mac) ?? .list
#else
            ItemLayout(rawValue: itemLayoutRaw_ios) ?? .list
#endif
        }
        set {
#if os(macOS)
            itemLayoutRaw_mac = newValue.rawValue
#else
            itemLayoutRaw_ios = newValue.rawValue
#endif
        }
    }

    var gridCardSize: Double {
        get {
#if os(macOS)
            gridCardSize_mac
#else
            gridCardSize_ios
#endif
        }
        set {
#if os(macOS)
            gridCardSize_mac = newValue
#else
            gridCardSize_ios = newValue
#endif
        }
    }
}

// MARK: - Relationship Accessors

/// Non-optional views of the `stored…` relationships, which CloudKit requires to be optional.
///
/// Must stay in an extension: `@Model` rewrites every `var` in the class body, computed ones
/// included, into a persisted accessor, which crashes on first access.
extension Catalogue {
    var fieldDefinitions: [FieldDefinition] {
        get { storedFieldDefinitions ?? [] }
        set { storedFieldDefinitions = newValue }
    }

    /// Always use this rather than sorting on `priority`: two devices adding a field before a
    /// merge produce equal priorities, and a per-device order makes synced derived columns
    /// (`tiebreakKey`, `searchText`) differ, so devices rewrite each other's forever.
    var sortedFieldDefinitions: [FieldDefinition] {
        fieldDefinitions.sorted(by: FieldDefinition.isOrderedBefore)
    }

    var items: [CatalogueItem] {
        get { storedItems ?? [] }
        set { storedItems = newValue }
    }
}
