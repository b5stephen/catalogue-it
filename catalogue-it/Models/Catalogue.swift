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

    @Relationship(deleteRule: .cascade, inverse: \FieldDefinition.catalogue)
    var fieldDefinitions: [FieldDefinition] = []

    @Relationship(deleteRule: .cascade, inverse: \CatalogueItem.catalogue)
    var items: [CatalogueItem] = []

    init(name: String, iconName: String = "square.grid.2x2", colorHex: String = "#007AFF") {
        self.name = name
        self.createdDate = Date.now
        self.iconName = iconName
        self.colorHex = colorHex
    }
}
