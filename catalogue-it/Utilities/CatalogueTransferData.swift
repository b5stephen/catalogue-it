//
//  CatalogueTransferData.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 26/03/2026.
//

import Foundation
import SwiftData

// MARK: - Export File Wrapper

/// Multi-catalogue even for a single export. A Data export of some items holds the whole
/// catalogue's setup and only those items.
nonisolated struct CatalogueExportFile: Codable {
    /// - v1: wishlist was an `isWishlist` boolean on each item.
    /// - v2: wishlist is an ordinary field with `displayRole: .statusTabs`, and catalogues have
    ///   `showAllTab`. v1 still imports — see `LegacyWishlistUpgrade`.
    static let currentVersion = 2

    var version: Int = CatalogueExportFile.currentVersion
    var exportedAt: Date
    var catalogues: [CatalogueDTO]
}

// MARK: - Catalogue DTO

nonisolated struct CatalogueDTO: Codable {
    var name: String
    var iconName: String
    /// Optional, and absent from older files: a photo or Genmoji icon, with `iconName` as its
    /// fallback. Exported even without photos, as it is small.
    var iconImageData: Data?
    var iconImageKind: String?
    var colorHex: String
    var createdDate: Date
    var priority: Int
    var sortFieldKey: String
    var sortDirection: String
    /// v2+. v1 files show the "All" tab.
    var showAllTab: Bool?
    var fieldDefinitions: [FieldDefinitionDTO]
    var items: [CatalogueItemDTO]
}

// MARK: - Field Definition DTO

nonisolated struct FieldDefinitionDTO: Codable {
    /// Preserved so `sortFieldKey` references stay valid after import.
    var fieldID: UUID
    var name: String
    var fieldType: FieldType
    var priority: Int
    var fieldOptions: FieldOptions?
    /// v2+.
    var displayRole: DisplayRole?
}

// MARK: - Catalogue Item DTO

nonisolated struct CatalogueItemDTO: Codable {
    var createdDate: Date
    /// Optional so older files decode; import falls back to `createdDate`, as the V1 → V2 store
    /// migration does.
    var modifiedDate: Date?
    /// v1 only, never written. See `LegacyWishlistUpgrade`.
    var isWishlist: Bool?
    var notes: String?
    var fieldValues: [FieldValueDTO]
    var photos: [ItemPhotoDTO]
}

// MARK: - Field Value DTO

nonisolated struct FieldValueDTO: Codable {
    /// Re-links values to definitions on import.
    var fieldDefinitionID: UUID
    var fieldType: FieldType
    var textValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?
}

// MARK: - Item Photo DTO

nonisolated struct ItemPhotoDTO: Codable {
    var imageData: Data
    var priority: Int
    var caption: String?
}

// MARK: - SwiftData Model → DTO (Export)

nonisolated extension CatalogueDTO {
    init(_ catalogue: Catalogue, items: [CatalogueItemDTO]) {
        name = catalogue.name
        iconName = catalogue.iconName
        iconImageData = catalogue.iconImageData
        iconImageKind = catalogue.iconImageKind
        colorHex = catalogue.colorHex
        createdDate = catalogue.createdDate
        priority = catalogue.priority
        sortFieldKey = catalogue.sortFieldKey
        sortDirection = catalogue.sortDirection
        showAllTab = catalogue.showAllTab
        fieldDefinitions = catalogue.sortedFieldDefinitions
            .map(FieldDefinitionDTO.init)
        self.items = items
    }
}

nonisolated extension FieldDefinitionDTO {
    var optionCount: Int {
        if case .optionList(let opts) = fieldOptions { return opts.options.count }
        return 0
    }

    /// Re-validated: a hand-edited file or newer build can name a role this type can't support.
    var validatedDisplayRole: DisplayRole {
        let declared = displayRole ?? .none
        guard FieldDefinitionValidation.supports(
            role: declared,
            fieldType: fieldType,
            optionCount: optionCount
        ) else { return .none }
        return declared
    }
}

nonisolated extension FieldDefinitionDTO {
    init(_ fd: FieldDefinition) {
        fieldID = fd.fieldID
        name = fd.name
        fieldType = fd.fieldType
        priority = fd.priority
        fieldOptions = fd.fieldOptions
        displayRole = fd.displayRole
    }
}

nonisolated extension CatalogueItemDTO {
    init(_ item: CatalogueItem, includePhotos: Bool = true) {
        createdDate = item.createdDate
        modifiedDate = item.modifiedDate
        isWishlist = nil
        notes = item.notes
        fieldValues = item.fieldValues.compactMap(FieldValueDTO.init)
        photos = includePhotos
            ? item.photos.sorted { $0.priority < $1.priority }.map(ItemPhotoDTO.init)
            : []
    }
}

nonisolated extension FieldValueDTO {
    /// `nil` for an orphaned value.
    init?(_ fv: FieldValue) {
        guard let def = fv.fieldDefinition else { return nil }
        fieldDefinitionID = def.fieldID
        fieldType = fv.fieldType
        textValue = fv.textValue
        numberValue = fv.numberValue
        dateValue = fv.dateValue
        boolValue = fv.boolValue
    }
}

nonisolated extension ItemPhotoDTO {
    init(_ photo: ItemPhoto) {
        imageData = photo.imageData
        priority = photo.priority
        caption = photo.caption
    }
}
