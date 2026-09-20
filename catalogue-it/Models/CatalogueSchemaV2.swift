//
//  CatalogueSchemaV2.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Schema V2 (frozen)

/// The model shape TestFlight builds 2–7 shipped with: V1 plus `CatalogueItem.modifiedDate`.
/// Frozen: nothing in the app uses these classes — they exist so `CatalogueMigrationPlan`
/// has a baseline to migrate *from*.
///
/// Every class is a verbatim copy of the live model at version 2.0.0, nested so the entity
/// names match while the Swift types stay distinct. Do not edit these to track the live
/// models; when the live models change again, add `CatalogueSchemaV4` and freeze V3 the
/// same way.
enum CatalogueSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

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
