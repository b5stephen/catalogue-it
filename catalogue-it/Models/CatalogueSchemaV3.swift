//
//  CatalogueSchemaV3.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Schema V3 (frozen)

/// The models as TestFlight builds 8–24 and 0.7.0 builds 1–3 shipped them, for
/// `CatalogueMigrationPlan` to migrate from. Nested so the entity names match while the Swift types stay distinct. Never edit to
/// track the live models.
enum CatalogueSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Catalogue.self,
            FieldDefinition.self,
            CatalogueItem.self,
            FieldValue.self,
            ItemPhoto.self,
        ]
    }

    @Model
    final class Catalogue {
        var name: String = ""
        var createdDate: Date = Date.now
        var iconName: String = "square.grid.2x2"
        var colorHex: String = "#007AFF"
        var priority: Int = 0
        // Literal defaults, not the live constants: a frozen schema must not move when they do.
        var sortFieldKey: String = "__dateAdded"
        var sortDirection: String = "asc"
        var pendingDeletion: Bool = false
        var showAllTab: Bool = false
        var layoutOptionsData: Data?
        var itemLayoutRaw_mac: String = "list"
        var itemLayoutRaw_ios: String = "list"
        var gridCardSize_mac: Double = 160
        var gridCardSize_ios: Double = 160

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

    @Model
    final class FieldDefinition {
        var fieldID: UUID = UUID()
        var name: String = ""
        var fieldType: FieldType = FieldType.text
        var priority: Int = 0
        var fieldOptions: FieldOptions?
        var displayRole: DisplayRole = DisplayRole.none
        var catalogue: Catalogue?

        @Relationship(deleteRule: .nullify, inverse: \FieldValue.fieldDefinition)
        var storedFieldValues: [FieldValue]? = []

        init(name: String, fieldType: FieldType, priority: Int = 0, fieldID: UUID = UUID(), displayRole: DisplayRole = .none) {
            self.fieldID = fieldID
            self.name = name
            self.fieldType = fieldType
            self.priority = priority
            self.displayRole = displayRole
        }
    }

    @Model
    final class CatalogueItem {
        #Index<CatalogueItem>(
            [\.statusValue],
            [\.createdDate],
            [\.statusValue, \.createdDate],
            [\.deletedDate],
            [\.deletedDate, \.statusValue],
            [\.deletedDate, \.searchText],
            [\.catalogue, \.deletedDate, \.createdDate],
            [\.catalogue, \.deletedDate, \.statusValue, \.createdDate]
        )

        var createdDate: Date = Date.now
        var modifiedDate: Date = Date.now
        var notes: String?
        var deletedDate: Date?
        var searchText: String = ""
        var statusValue: String = ""
        var flagKeys: String = ""
        var catalogue: Catalogue?

        @Relationship(deleteRule: .cascade, inverse: \FieldValue.item)
        var storedFieldValues: [FieldValue]? = []

        @Relationship(deleteRule: .cascade, inverse: \ItemPhoto.item)
        var storedPhotos: [ItemPhoto]? = []

        init(notes: String? = nil) {
            self.createdDate = Date.now
            self.notes = notes
        }
    }

    @Model
    final class FieldValue {
        #Index<FieldValue>([\.fieldDefinition, \.sortKey, \.tiebreakKey])

        var fieldDefinition: FieldDefinition?
        var fieldType: FieldType = FieldType.text
        var item: CatalogueItem?
        var textValue: String?
        var numberValue: Double?
        var dateValue: Date?
        var boolValue: Bool?
        var sortKey: String = "\u{FFFF}"
        var tiebreakKey: String = "\u{FFFF}"

        init(fieldDefinition: FieldDefinition?, fieldType: FieldType) {
            self.fieldDefinition = fieldDefinition
            self.fieldType = fieldType
        }
    }

    @Model
    final class ItemPhoto {
        @Attribute(.externalStorage) var imageData: Data = Data()
        @Attribute(.externalStorage) var thumbnailData: Data?
        var priority: Int = 0
        var caption: String?
        var item: CatalogueItem?

        init(imageData: Data, thumbnailData: Data? = nil, priority: Int = 0, caption: String? = nil) {
            self.imageData = imageData
            self.thumbnailData = thumbnailData
            self.priority = priority
            self.caption = caption
        }
    }
}
