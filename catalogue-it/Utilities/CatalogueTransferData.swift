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
    /// Format history:
    /// - v1: wishlist was a hardcoded `isWishlist` boolean on each item.
    /// - v2: wishlist is an ordinary field carrying `displayRole: .statusTabs`;
    ///       catalogues gained `showAllTab`. v1 files still import — see `LegacyWishlistUpgrade`.
    static let currentVersion = 2

    var version: Int = CatalogueExportFile.currentVersion
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
    /// Added in v2. Absent in v1 files, which default to showing the "All" tab.
    var showAllTab: Bool?
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
    /// Added in v2. Absent in v1 files, where every field was an ordinary field.
    var displayRole: DisplayRole?
}

// MARK: - Catalogue Item DTO

struct CatalogueItemDTO: Codable {
    var createdDate: Date
    /// Decode-only, for v1 files. Never written on export (Optionals are omitted by the
    /// synthesised encoder) — wishlist is a regular field value in v2.
    /// See `LegacyWishlistUpgrade` for how this is converted on import.
    var isWishlist: Bool?
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
        showAllTab = catalogue.showAllTab
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
    /// Number of option-list options this DTO declares, or 0 for other field types.
    var optionCount: Int {
        if case .optionList(let opts) = fieldOptions { return opts.options.count }
        return 0
    }

    /// The display role to apply on import, re-validated against the field type.
    /// A file can name a role its type can't support — hand-edited, or written by a newer
    /// build with types this one doesn't have — and must not produce a broken tab bar.
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
        isWishlist = nil   // v2 exports carry status as a field value, not a flag
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
    /// - Parameters:
    ///   - priorityOffset: Added to the stored priority so the imported catalogue
    ///     appends after any existing catalogues rather than colliding with them.
    ///   - onProgress: Called on the main actor after each item is processed.
    ///     Receives (completedItems, totalItems).
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
        catalogue.sortFieldKey = sortFieldKey
        catalogue.sortDirection = sortDirection
        // Absent only in v1 files, where the item list always had an "All" tab. New
        // catalogues default it off, but an import should reproduce the file's own UI
        // rather than quietly dropping a tab the user was using.
        catalogue.showAllTab = showAllTab ?? true
        context.insert(catalogue)

        // v1 files carry wishlist as a per-item boolean with no field backing it. Synthesise
        // the status field they'd have in v2, then materialise a value for it on each item below.
        let legacyStatusField = LegacyWishlistUpgrade.synthesisedStatusField(for: self)
        let allFieldDefinitionDTOs = fieldDefinitions + (legacyStatusField.map { [$0] } ?? [])

        // Create FieldDefinitions preserving original fieldIDs so that
        // sortFieldKey references remain valid after import.
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
        let sortedFieldDefs = defMap.values.sorted { $0.priority < $1.priority }

        // At most one status field may exist. A file with several (hand-edited, or merged
        // by hand) keeps the lowest-priority one and demotes the rest to ordinary fields.
        var seenStatusField = false
        for def in sortedFieldDefs where def.displayRole == .statusTabs {
            if seenStatusField {
                def.displayRole = .none
            } else {
                seenStatusField = true
            }
        }

        // Create items, linking field values back to definitions via UUID map.
        // Thumbnails are written to the filesystem cache (not the model) to avoid bloating
        // CatalogueItem SQLite rows. We accumulate (item, thumbData) pairs and flush them
        // to disk after each batch save so that permanent PersistentIdentifiers are available.
        var pendingThumbnails: [(CatalogueItem, Data)] = []

        for (index, itemDTO) in items.enumerated() {
            let item = CatalogueItem(notes: itemDTO.notes)
            item.createdDate = itemDTO.createdDate
            item.catalogue = catalogue
            context.insert(item)

            // Append the migrated wishlist value for v1 files so the synthesised status
            // field actually has data behind it.
            let itemFieldValueDTOs = itemDTO.fieldValues + (legacyStatusField.map {
                [LegacyWishlistUpgrade.statusFieldValue(for: itemDTO, fieldID: $0.fieldID)]
            } ?? [])

            var createdFieldValues: [FieldValue] = []
            for fvDTO in itemFieldValueDTOs {
                // Skip values whose definition wasn't found (handles corrupt/partial files).
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
            for fv in createdFieldValues {
                fv.tiebreakKey = SortKeyEncoder.tiebreakKey(
                    for: fv,
                    allFieldValuesOnItem: createdFieldValues,
                    fieldDefinitionsByPriority: sortedFieldDefs,
                    itemCreatedDate: item.createdDate
                )
            }
            item.searchText = SearchTextBuilder.build(from: createdFieldValues)
            ItemFacetBuilder.apply(to: item, fieldValues: createdFieldValues, definitions: sortedFieldDefs)

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

        // Flush thumbnails for the final partial batch (< 200 items).
        if !pendingThumbnails.isEmpty {
            try? context.save()
            for (savedItem, data) in pendingThumbnails {
                ThumbnailLoader.writeThumbnailToCache(data, for: savedItem.persistentModelID)
            }
        }

        return catalogue
    }

}

