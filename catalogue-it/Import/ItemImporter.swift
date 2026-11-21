//
//  ItemImporter.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Import Summary

nonisolated struct ImportSummary: Sendable {
    /// The catalogues created, or the one imported into.
    var catalogueIDs: [PersistentIdentifier] = []
    /// What Undo Import moves to Recently Deleted.
    var insertedItemIDs: [PersistentIdentifier] = []
    var skippedDuplicateCount = 0
    var addedFieldCount = 0
    var addedOptionCount = 0
}

// MARK: - Item Importer

/// Writes a Data file's catalogues on its own context, in batches. A ModelActor runs on the
/// calling task's thread, so enter it with `Task.detached`. Its context has no undo manager,
/// so nothing imported lands on the undo stack; Undo Import soft-deletes `insertedItemIDs`.
@ModelActor
actor ItemImporter {
    private static let batchSize = 200

    typealias Progress = @Sendable (_ done: Int, _ total: Int) -> Void

    enum ImporterError: Error {
        case catalogueMissing
    }

    // MARK: New Catalogues

    /// Expects a file from `CatalogueImporter.decode`, which has already upgraded v1 wishlists.
    /// - Parameter priorityOffset: Pass the existing catalogue count, so imports append.
    func importAsNewCatalogues(
        _ file: CatalogueExportFile,
        priorityOffset: Int,
        onProgress: Progress = { _, _ in }
    ) throws -> ImportSummary {
        let total = file.catalogues.reduce(0) { $0 + $1.items.count }
        var summary = ImportSummary()
        var doneBefore = 0
        onProgress(0, total)

        for dto in file.catalogues {
            let catalogue = Catalogue(
                name: dto.name,
                iconName: dto.iconName,
                colorHex: dto.colorHex,
                priority: dto.priority + priorityOffset
            )
            modelContext.insert(catalogue)
            catalogue.createdDate = dto.createdDate
            catalogue.iconImageData = dto.iconImageData
            catalogue.iconImageKind = dto.iconImageKind
            catalogue.sortFieldKey = dto.sortFieldKey
            catalogue.sortDirection = dto.sortDirection
            // v1 always had an "All" tab; reproduce the file's UI rather than drop a tab in use.
            catalogue.showAllTab = dto.showAllTab ?? true

            // Original fieldIDs, so `sortFieldKey` references stay valid.
            var fieldMap: [UUID: FieldDefinition] = [:]
            for fieldDTO in dto.fieldDefinitions {
                let definition = FieldDefinition(
                    name: fieldDTO.name,
                    fieldType: fieldDTO.fieldType,
                    priority: fieldDTO.priority,
                    fieldID: fieldDTO.fieldID,
                    displayRole: fieldDTO.validatedDisplayRole
                )
                modelContext.insert(definition)
                definition.fieldOptions = fieldDTO.fieldOptions
                definition.catalogue = catalogue
                fieldMap[fieldDTO.fieldID] = definition
            }
            let definitions = fieldMap.values.sorted(by: FieldDefinition.isOrderedBefore)

            // A file with several status fields keeps the first and demotes the rest.
            var seenStatusField = false
            for definition in definitions where definition.displayRole == .statusTabs {
                if seenStatusField { definition.displayRole = .none } else { seenStatusField = true }
            }

            let before = doneBefore
            summary.insertedItemIDs += try writeItems(
                dto.items, to: catalogue, fieldMap: fieldMap, definitions: definitions
            ) { done in onProgress(before + done, total) }
            doneBefore += dto.items.count
            summary.catalogueIDs.append(catalogue.persistentModelID)
        }
        return summary
    }

    // MARK: Existing Catalogue

    /// Fields are matched by `ImportFieldMatcher`; unmatched ones are added after the
    /// catalogue's own, never as its status field (its items would have no value for it).
    /// Option-list values the matched field lacks are added to its options. The catalogue's own
    /// settings — name, icon, sort, tabs — are left alone.
    ///
    /// - Parameters:
    ///   - skippingDuplicates: Leaves out items whose `createdDate` matches a live item already
    ///     in the catalogue: the same item, exported from here or imported before.
    ///   - matchingFieldsByName: See `ImportFieldMatcher.match(_:to:byName:)`.
    func importCatalogue(
        _ dto: CatalogueDTO,
        into catalogueID: PersistentIdentifier,
        skippingDuplicates: Bool,
        matchingFieldsByName: Bool = true,
        onProgress: Progress = { _, _ in }
    ) throws -> ImportSummary {
        guard let catalogue = modelContext.model(for: catalogueID) as? Catalogue else {
            throw ImporterError.catalogueMissing
        }
        var summary = ImportSummary(catalogueIDs: [catalogueID])

        let existingDefinitions = catalogue.fieldDefinitions
        let existingByID = Dictionary(existingDefinitions.map { ($0.fieldID, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = ImportFieldMatcher.match(
            dto.fieldDefinitions, to: existingDefinitions.map(ImportFieldMatcher.ExistingField.init), byName: matchingFieldsByName)
        let fileFields = Dictionary(dto.fieldDefinitions.map { ($0.fieldID, $0) }, uniquingKeysWith: { first, _ in first })

        var fieldMap: [UUID: FieldDefinition] = [:]
        var addedDefinitions: [FieldDefinition] = []
        var nextPriority = (existingDefinitions.map(\.priority).max() ?? -1) + 1

        for entry in entries {
            guard let fileField = fileFields[entry.fileFieldID] else { continue }
            switch entry.match {
            case .existing(let fieldID, _):
                guard let definition = existingByID[fieldID] else { continue }
                fieldMap[entry.fileFieldID] = definition
            case .new(let name):
                let role = fileField.validatedDisplayRole
                // A fresh ID: the file's may already belong to a field of another catalogue.
                let definition = FieldDefinition(
                    name: name,
                    fieldType: fileField.fieldType,
                    priority: nextPriority,
                    displayRole: role == .statusTabs ? .none : role
                )
                modelContext.insert(definition)
                definition.fieldOptions = fileField.fieldOptions
                definition.catalogue = catalogue
                nextPriority += 1
                fieldMap[entry.fileFieldID] = definition
                addedDefinitions.append(definition)
            }
        }
        summary.addedFieldCount = addedDefinitions.count

        var items = dto.items
        if skippingDuplicates {
            let existingDates = try Self.liveCreatedDates(of: catalogueID, in: modelContext)
            items.removeAll { existingDates.contains($0.createdDate) }
            summary.skippedDuplicateCount = dto.items.count - items.count
        }

        summary.addedOptionCount = addMissingOptions(used: items, fieldMap: fieldMap, existing: Set(existingByID.keys))

        let definitions = (existingDefinitions + addedDefinitions).sorted(by: FieldDefinition.isOrderedBefore)
        // Every tiebreakKey encodes the item's other fields in order, so a new field changes
        // the keys of the items already here.
        if !addedDefinitions.isEmpty {
            try refreshLiveItems(of: catalogueID, definitions: definitions)
        }

        summary.insertedItemIDs = try writeItems(
            items, to: catalogue, fieldMap: fieldMap, definitions: definitions
        ) { done in onProgress(done, items.count) }
        return summary
    }

    /// The `createdDate`s of the catalogue's live items, which identify an item across export
    /// and import.
    nonisolated static func liveCreatedDates(of catalogueID: PersistentIdentifier, in context: ModelContext) throws -> Set<Date> {
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: #Predicate {
            $0.catalogue?.persistentModelID == catalogueID && $0.deletedDate == nil
        })
        descriptor.propertiesToFetch = [\.createdDate]
        return Set(try context.fetch(descriptor).map(\.createdDate))
    }

    // MARK: Writing

    /// Appends the values each existing option-list field is given but doesn't list. Returns
    /// how many were added.
    private func addMissingOptions(used items: [CatalogueItemDTO], fieldMap: [UUID: FieldDefinition], existing: Set<UUID>) -> Int {
        var added = 0
        var newOptions: [UUID: [String]] = [:]
        for item in items {
            for value in item.fieldValues where value.fieldType == .optionList {
                guard let definition = fieldMap[value.fieldDefinitionID],
                      existing.contains(definition.fieldID),
                      definition.fieldType == .optionList,
                      let text = value.textValue, !text.isEmpty else { continue }
                let current = definition.optionListOptions?.options ?? []
                var pending = newOptions[definition.fieldID, default: []]
                guard !current.contains(text), !pending.contains(text) else { continue }
                pending.append(text)
                newOptions[definition.fieldID] = pending
            }
        }
        for (fieldID, options) in newOptions {
            guard let definition = fieldMap.values.first(where: { $0.fieldID == fieldID }) else { continue }
            var listOptions = definition.optionListOptions ?? OptionListOptions()
            listOptions.options += options
            definition.optionListOptions = listOptions
            added += options.count
        }
        return added
    }

    private func refreshLiveItems(of catalogueID: PersistentIdentifier, definitions: [FieldDefinition]) throws {
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: #Predicate {
            $0.catalogue?.persistentModelID == catalogueID && $0.deletedDate == nil
        })
        descriptor.relationshipKeyPathsForPrefetching = [\.storedFieldValues]
        for (index, item) in try modelContext.fetch(descriptor).enumerated() {
            ItemDerivedColumns.refresh(on: item, fieldValues: item.fieldValues, definitions: definitions)
            if (index + 1) % Self.batchSize == 0 { try modelContext.save() }
        }
        try modelContext.save()
    }

    /// Saved per batch; IDs are collected after each save, once they are permanent. Thumbnails
    /// go to the file cache, which is keyed by those IDs.
    private func writeItems(
        _ dtos: [CatalogueItemDTO],
        to catalogue: Catalogue,
        fieldMap: [UUID: FieldDefinition],
        definitions: [FieldDefinition],
        onProgress: (Int) -> Void
    ) throws -> [PersistentIdentifier] {
        var inserted: [PersistentIdentifier] = []
        var batch: [(item: CatalogueItem, thumbnail: Data?)] = []

        func flush() throws {
            try modelContext.save()
            for (item, thumbnail) in batch {
                inserted.append(item.persistentModelID)
                if let thumbnail { ThumbnailLoader.writeThumbnailToCache(thumbnail, for: item.persistentModelID) }
            }
            batch.removeAll()
        }

        onProgress(0)
        for (index, dto) in dtos.enumerated() {
            try Task.checkCancellation()
            let item = CatalogueItem(notes: dto.notes)
            modelContext.insert(item)
            item.createdDate = dto.createdDate
            item.modifiedDate = dto.modifiedDate ?? dto.createdDate
            item.catalogue = catalogue

            var values: [FieldValue] = []
            for valueDTO in dto.fieldValues {
                // A value whose definition is missing or of another type is from a corrupt or
                // partial file.
                guard let definition = fieldMap[valueDTO.fieldDefinitionID],
                      definition.fieldType == valueDTO.fieldType else { continue }
                let value = FieldValue(fieldDefinition: nil, fieldType: valueDTO.fieldType)
                modelContext.insert(value)
                value.fieldDefinition = definition
                value.textValue = valueDTO.textValue
                value.numberValue = valueDTO.numberValue
                value.dateValue = valueDTO.dateValue
                value.boolValue = valueDTO.boolValue
                value.item = item
                values.append(value)
            }
            ItemDerivedColumns.refresh(on: item, fieldValues: values, definitions: definitions)

            for photoDTO in dto.photos {
                let photo = ItemPhoto(imageData: photoDTO.imageData, priority: photoDTO.priority, caption: photoDTO.caption)
                modelContext.insert(photo)
                photo.item = item
            }
            let cover = dto.photos.min { $0.priority < $1.priority }
            batch.append((item, cover.flatMap { makeThumbnailData(from: $0.imageData) }))

            if (index + 1) % Self.batchSize == 0 { try flush() }
            onProgress(index + 1)
        }
        try flush()
        return inserted
    }
}
