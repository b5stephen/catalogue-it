//
//  CatalogueTransferData.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 26/03/2026.
//

import Foundation
import SwiftData

// MARK: - Export File Wrapper

/// Multi-catalogue even for a single export.
struct CatalogueExportFile: Codable {
    /// - v1: wishlist was an `isWishlist` boolean on each item.
    /// - v2: wishlist is an ordinary field with `displayRole: .statusTabs`, and catalogues have
    ///   `showAllTab`. v1 still imports — see `LegacyWishlistUpgrade`.
    static let currentVersion = 2

    var version: Int = CatalogueExportFile.currentVersion
    var exportedAt: Date
    var catalogues: [CatalogueDTO]
}

// MARK: - Catalogue DTO

struct CatalogueDTO: Codable {
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

struct FieldDefinitionDTO: Codable {
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

struct CatalogueItemDTO: Codable {
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

struct FieldValueDTO: Codable {
    /// Re-links values to definitions on import.
    var fieldDefinitionID: UUID
    var fieldType: FieldType
    var textValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?
}

// MARK: - Item Photo DTO

struct ItemPhotoDTO: Codable {
    var imageData: Data
    var priority: Int
    var caption: String?
}

// MARK: - SwiftData Model → DTO (Export)

extension CatalogueDTO {
    init(_ catalogue: Catalogue, includePhotos: Bool = true) {
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
        items = catalogue.items
            .filter { $0.deletedDate == nil }
            .sorted { $0.createdDate < $1.createdDate }
            .map { CatalogueItemDTO($0, includePhotos: includePhotos) }
    }
}

extension FieldDefinitionDTO {
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

extension FieldDefinitionDTO {
    init(_ fd: FieldDefinition) {
        fieldID = fd.fieldID
        name = fd.name
        fieldType = fd.fieldType
        priority = fd.priority
        fieldOptions = fd.fieldOptions
        displayRole = fd.displayRole
    }
}

extension CatalogueItemDTO {
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

extension FieldValueDTO {
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

extension ItemPhotoDTO {
    init(_ photo: ItemPhoto) {
        imageData = photo.imageData
        priority = photo.priority
        caption = photo.caption
    }
}

// MARK: - DTO → SwiftData Model (Import)

extension CatalogueDTO {
    /// - Parameters:
    ///   - priorityOffset: Appends after existing catalogues rather than colliding.
    ///   - onProgress: (completed, total) on the main actor after each item.
    @MainActor
    func makeCatalogue(
        in context: ModelContext,
        priorityOffset: Int,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> Catalogue {
        let catalogue = Catalogue(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            priority: priority + priorityOffset
        )
        catalogue.createdDate = createdDate
        catalogue.iconImageData = iconImageData
        catalogue.iconImageKind = iconImageKind
        catalogue.sortFieldKey = sortFieldKey
        catalogue.sortDirection = sortDirection
        // v1 always had an "All" tab; reproduce the file's UI rather than drop a tab in use.
        catalogue.showAllTab = showAllTab ?? true
        context.insert(catalogue)

        // v1 wishlist has no backing field: synthesise the v2 status field, with values below.
        let legacyStatusField = LegacyWishlistUpgrade.synthesisedStatusField(for: self)
        let allFieldDefinitionDTOs = fieldDefinitions + (legacyStatusField.map { [$0] } ?? [])

        // Original fieldIDs, so `sortFieldKey` references stay valid.
        var defMap: [UUID: FieldDefinition] = [:]
        for fdDTO in allFieldDefinitionDTOs {
            let fd = FieldDefinition(
                name: fdDTO.name,
                fieldType: fdDTO.fieldType,
                priority: fdDTO.priority,
                fieldID: fdDTO.fieldID,
                displayRole: fdDTO.validatedDisplayRole
            )
            fd.fieldOptions = fdDTO.fieldOptions
            fd.catalogue = catalogue
            context.insert(fd)
            defMap[fdDTO.fieldID] = fd
        }
        let sortedFieldDefs = defMap.values.sorted(by: FieldDefinition.isOrderedBefore)

        // A file with several status fields keeps the first and demotes the rest.
        var seenStatusField = false
        for def in sortedFieldDefs where def.displayRole == .statusTabs {
            if seenStatusField {
                def.displayRole = .none
            } else {
                seenStatusField = true
            }
        }

        // Thumbnails go to the file cache, not the model, flushed after each batch save once
        // permanent identifiers exist.
        var pendingThumbnails: [(CatalogueItem, Data)] = []

        for (index, itemDTO) in items.enumerated() {
            let item = CatalogueItem(notes: itemDTO.notes)
            item.createdDate = itemDTO.createdDate
            item.modifiedDate = itemDTO.modifiedDate ?? itemDTO.createdDate
            item.catalogue = catalogue
            context.insert(item)

            let itemFieldValueDTOs = itemDTO.fieldValues + (legacyStatusField.map {
                [LegacyWishlistUpgrade.statusFieldValue(for: itemDTO, fieldID: $0.fieldID)]
            } ?? [])

            var createdFieldValues: [FieldValue] = []
            for fvDTO in itemFieldValueDTOs {
                // Skip values whose definition is missing (a corrupt or partial file).
                guard let def = defMap[fvDTO.fieldDefinitionID] else { continue }
                let fv = FieldValue(fieldDefinition: def, fieldType: fvDTO.fieldType)
                fv.textValue = fvDTO.textValue
                fv.numberValue = fvDTO.numberValue
                fv.dateValue = fvDTO.dateValue
                fv.boolValue = fvDTO.boolValue
                fv.sortKey = SortKeyEncoder.sortKey(for: fv)
                fv.item = item
                context.insert(fv)
                createdFieldValues.append(fv)
            }
            ItemDerivedColumns.refresh(on: item, fieldValues: createdFieldValues, definitions: sortedFieldDefs)

            for photoDTO in itemDTO.photos {
                let photo = ItemPhoto(
                    imageData: photoDTO.imageData,
                    priority: photoDTO.priority,
                    caption: photoDTO.caption
                )
                photo.item = item
                context.insert(photo)
            }

            if let coverPhotoDTO = itemDTO.photos.min(by: { $0.priority < $1.priority }),
               let thumbData = makeThumbnailData(from: coverPhotoDTO.imageData) {
                pendingThumbnails.append((item, thumbData))
            }

            onProgress?(index + 1, items.count)
            if index % 20 == 19 {
                await Task.yield()
            }
            if (index + 1) % 200 == 0 {
                try? context.save()
                for (savedItem, data) in pendingThumbnails {
                    ThumbnailLoader.writeThumbnailToCache(data, for: savedItem.persistentModelID)
                }
                pendingThumbnails = []
            }
        }

        if !pendingThumbnails.isEmpty {
            try? context.save()
            for (savedItem, data) in pendingThumbnails {
                ThumbnailLoader.writeThumbnailToCache(data, for: savedItem.persistentModelID)
            }
        }

        return catalogue
    }

}

