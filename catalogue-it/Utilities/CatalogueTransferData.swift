//
//  CatalogueTransferData.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 26/03/2026.
//

import Foundation
import SwiftData

// MARK: - Export File Wrapper

/// Top-level container for a catalogue export file.
/// Holds a version field for future format changes and an array of catalogues
/// (enabling multi-catalogue files even when exporting a single catalogue).
struct CatalogueExportFile: Codable {
    var version: Int = 1
    var exportedAt: Date
    var catalogues: [CatalogueDTO]
}

// MARK: - Catalogue DTO

struct CatalogueDTO: Codable {
    var name: String
    var iconName: String
    var colorHex: String
    var createdDate: Date
    var priority: Int
    var sortFieldKey: String
    var sortDirection: String
    var fieldDefinitions: [FieldDefinitionDTO]
    var items: [CatalogueItemDTO]
}

// MARK: - Field Definition DTO

struct FieldDefinitionDTO: Codable {
    /// Preserved verbatim so that sortFieldKey references remain valid after import.
    var fieldID: UUID
    var name: String
    var fieldType: FieldType
    var priority: Int
    var fieldOptions: FieldOptions?
}

// MARK: - Catalogue Item DTO

struct CatalogueItemDTO: Codable {
    var createdDate: Date
    var isWishlist: Bool
    var notes: String?
    var fieldValues: [FieldValueDTO]
    var photos: [ItemPhotoDTO]
}

// MARK: - Field Value DTO

struct FieldValueDTO: Codable {
    /// Matches FieldDefinitionDTO.fieldID — used to re-link values to definitions on import.
    var fieldDefinitionID: UUID
    var fieldType: FieldType
    var textValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?
}

// MARK: - Item Photo DTO

struct ItemPhotoDTO: Codable {
    /// Data encodes as base64 in JSON automatically via Codable.
    var imageData: Data
    var priority: Int
    var caption: String?
}

// MARK: - SwiftData Model → DTO (Export)

extension CatalogueDTO {
    init(_ catalogue: Catalogue, includePhotos: Bool = true) {
        name = catalogue.name
        iconName = catalogue.iconName
        colorHex = catalogue.colorHex
        createdDate = catalogue.createdDate
        priority = catalogue.priority
        sortFieldKey = catalogue.sortFieldKey
        sortDirection = catalogue.sortDirection
        fieldDefinitions = catalogue.fieldDefinitions
            .sorted { $0.priority < $1.priority }
            .map(FieldDefinitionDTO.init)
        items = catalogue.items
            .filter { $0.deletedDate == nil }
            .sorted { $0.createdDate < $1.createdDate }
            .map { CatalogueItemDTO($0, includePhotos: includePhotos) }
    }
}

extension FieldDefinitionDTO {
    init(_ fd: FieldDefinition) {
        fieldID = fd.fieldID
        name = fd.name
        fieldType = fd.fieldType
        priority = fd.priority
        fieldOptions = fd.fieldOptions
    }
}

extension CatalogueItemDTO {
    init(_ item: CatalogueItem, includePhotos: Bool = true) {
        createdDate = item.createdDate
        isWishlist = item.isWishlist
        notes = item.notes
        fieldValues = item.fieldValues.compactMap(FieldValueDTO.init)
        photos = includePhotos
            ? item.photos.sorted { $0.priority < $1.priority }.map(ItemPhotoDTO.init)
            : []
    }
}

extension FieldValueDTO {
    /// Returns nil if the field value has no associated definition (defensive — skips orphaned values).
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
    /// Creates a new Catalogue (and all its children) in the given context.
    /// - Parameter priorityOffset: Added to the stored priority so the imported catalogue
    ///   appends after any existing catalogues rather than colliding with them.
    @MainActor
    func makeCatalogue(in context: ModelContext, priorityOffset: Int) -> Catalogue {
        let catalogue = Catalogue(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            priority: priority + priorityOffset
        )
        catalogue.createdDate = createdDate
        catalogue.sortFieldKey = sortFieldKey
        catalogue.sortDirection = sortDirection
        context.insert(catalogue)

        // Create FieldDefinitions preserving original fieldIDs so that
        // sortFieldKey references remain valid after import.
        var defMap: [UUID: FieldDefinition] = [:]
        for fdDTO in fieldDefinitions {
            let fd = FieldDefinition(
                name: fdDTO.name,
                fieldType: fdDTO.fieldType,
                priority: fdDTO.priority,
                fieldID: fdDTO.fieldID
            )
            fd.fieldOptions = fdDTO.fieldOptions
            fd.catalogue = catalogue
            context.insert(fd)
            defMap[fdDTO.fieldID] = fd
        }

        // Create items, linking field values back to definitions via UUID map.
        for itemDTO in items {
            let item = CatalogueItem(isWishlist: itemDTO.isWishlist, notes: itemDTO.notes)
            item.createdDate = itemDTO.createdDate
            item.catalogue = catalogue
            context.insert(item)

            for fvDTO in itemDTO.fieldValues {
                // Skip values whose definition wasn't found (handles corrupt/partial files).
                guard let def = defMap[fvDTO.fieldDefinitionID] else { continue }
                let fv = FieldValue(fieldDefinition: def, fieldType: fvDTO.fieldType)
                fv.textValue = fvDTO.textValue
                fv.numberValue = fvDTO.numberValue
                fv.dateValue = fvDTO.dateValue
                fv.boolValue = fvDTO.boolValue
                fv.item = item
                context.insert(fv)
            }

            for photoDTO in itemDTO.photos {
                let photo = ItemPhoto(
                    imageData: photoDTO.imageData,
                    priority: photoDTO.priority,
                    caption: photoDTO.caption
                )
                photo.item = item
                context.insert(photo)
            }
        }

        return catalogue
    }
}
