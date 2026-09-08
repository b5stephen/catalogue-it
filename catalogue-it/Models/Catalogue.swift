//
//  Catalogue.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData


// MARK: - Catalogue

/// Represents a collection (e.g., "Model Planes", "Stamp Collection")
@Model
final class Catalogue {
    // Every stored property below carries a default value: CloudKit rejects
    // non-optional attributes that have none, and the container fails to build.
    var name: String = ""
    var createdDate: Date = Date.now
    var iconName: String = "square.grid.2x2" // SF Symbol name
    var colorHex: String = "#007AFF" // Stored as hex string
    var priority: Int = 0

    var sortFieldKey: String = ItemSortField.dateAdded.rawValue
    var sortDirection: String = ItemSortDirection.ascending.rawValue

    /// True once the user has confirmed deletion. The catalogue is hidden from the UI
    /// immediately and its graph is torn down by `BackgroundDeletionActor`; the flag
    /// persists (and syncs) so an interrupted deletion resumes on next launch.
    var pendingDeletion: Bool = false

    /// Whether the synthetic "All" tab is shown ahead of the status field's own tabs.
    /// Only meaningful when the catalogue has a `.statusTabs` field.
    /// Off by default — a status field is usually added because the user wants to work in
    /// one state at a time; the catch-all tab is opt-in.
    var showAllTab: Bool = false

    var itemLayoutRaw_mac: String = ItemLayout.list.rawValue
    var itemLayoutRaw_ios: String = ItemLayout.list.rawValue
    var gridCardSize_mac: Double = Double(AppConstants.GridCardSize.defaultSize)
    var gridCardSize_ios: Double = Double(AppConstants.GridCardSize.defaultSize)

    // CloudKit requires every relationship to be optional, so the persisted properties are
    // optional arrays and the app reads them through the non-optional accessors below.
    // Nothing outside this file should touch the `stored…` properties, except a
    // `relationshipKeyPathsForPrefetching` key path, which must name the persisted property.
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

// MARK: - Per-Platform Preferences

extension Catalogue {
    /// Item layout (list vs. gallery) for this catalogue, on the current platform.
    /// Mac and iOS/iPadOS are stored separately so the same synced catalogue can
    /// show a different layout on each platform.
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

    /// Gallery card zoom size for this catalogue, on the current platform.
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

/// The `stored…` relationships are optional because CloudKit requires it. These accessors give
/// the rest of the app the non-optional collections it has always used.
///
/// They live in an extension deliberately: the `@Model` macro rewrites *every* `var` in the
/// class body into a persisted accessor, computed properties included, and the result is a
/// runtime crash on first access ("Couldn't find \\CatalogueItem.fieldValues"). The macro does
/// not touch extensions.
extension Catalogue {
    var fieldDefinitions: [FieldDefinition] {
        get { storedFieldDefinitions ?? [] }
        set { storedFieldDefinitions = newValue }
    }

    var items: [CatalogueItem] {
        get { storedItems ?? [] }
        set { storedItems = newValue }
    }
}
