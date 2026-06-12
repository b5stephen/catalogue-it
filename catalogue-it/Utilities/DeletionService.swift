//
//  DeletionService.swift
//  catalogue-it
//

import Foundation
import SwiftData
import os

@MainActor
enum DeletionService {
    private static let logger = Logger(subsystem: "catalogue-it", category: "DeletionService")

    /// Manually deletes an item and its children bottom-up. Avoids SwiftData's automatic cascade
    /// touching FieldValue via two conflicting delete rules in one pass (CatalogueItem.fieldValues
    /// = .cascade and FieldDefinition.fieldValues = .nullify), which corrupts the delete snapshot.
    /// Does NOT save — caller saves once after a batch.
    static func deleteItem(_ item: CatalogueItem, in context: ModelContext) {
        for photo in Array(item.photos) { context.delete(photo) }
        for value in Array(item.fieldValues) { context.delete(value) }
        context.delete(item)
    }

    /// Manually deletes a catalogue and its entire graph bottom-up (items + their children first,
    /// then field definitions whose fieldValues are now already gone, then the catalogue itself).
    static func deleteCatalogue(_ catalogue: Catalogue, in context: ModelContext) {
        for item in Array(catalogue.items) { deleteItem(item, in: context) }
        for definition in Array(catalogue.fieldDefinitions) { context.delete(definition) }
        context.delete(catalogue)
    }

    static func deleteCatalogueAndSave(_ catalogue: Catalogue, in context: ModelContext) {
        deleteCatalogue(catalogue, in: context)
        save(context)
    }

    static func deleteItemsAndSave(_ items: [CatalogueItem], in context: ModelContext) {
        for item in items { deleteItem(item, in: context) }
        save(context)
    }

    private static func save(_ context: ModelContext) {
        do { try context.save() }
        catch { logger.error("Delete save failed: \(error.localizedDescription, privacy: .public)") }
    }
}
