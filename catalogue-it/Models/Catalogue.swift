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
    var name: String
    var createdDate: Date
    var iconName: String // SF Symbol name
    var colorHex: String // Stored as hex string
    var priority: Int

    var sortFieldKey: String = ItemSortField.dateAdded.rawValue
    var sortDirection: String = ItemSortDirection.ascending.rawValue

    /// True once the user has confirmed deletion. The catalogue is hidden from the UI
    /// immediately and its graph is torn down by `BackgroundDeletionActor`; the flag
    /// persists (and syncs) so an interrupted deletion resumes on next launch.
    var pendingDeletion: Bool = false

    var itemLayoutRaw_mac: String = ItemLayout.list.rawValue
    var itemLayoutRaw_ios: String = ItemLayout.list.rawValue
    var gridCardSize_mac: Double = Double(AppConstants.GridCardSize.defaultSize)
    var gridCardSize_ios: Double = Double(AppConstants.GridCardSize.defaultSize)

    @Relationship(deleteRule: .cascade, inverse: \FieldDefinition.catalogue)
    var fieldDefinitions: [FieldDefinition] = []

    @Relationship(deleteRule: .cascade, inverse: \CatalogueItem.catalogue)
    var items: [CatalogueItem] = []

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
