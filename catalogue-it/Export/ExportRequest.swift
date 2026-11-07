//
//  ExportRequest.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Export Items

/// What the composer is opened on: every ID, and the first few items loaded for its preview
/// and Message.
struct ExportItems {
    let ids: [PersistentIdentifier]
    /// In `ids` order, at most `ExportFormat.messageItemLimit`.
    let items: [CatalogueItem]

    init(items: [CatalogueItem]) {
        ids = items.map(\.persistentModelID)
        self.items = items
    }

    @MainActor
    init(ids: [PersistentIdentifier], in context: ModelContext) {
        self.ids = ids
        let wanted = Array(ids.prefix(ExportFormat.messageItemLimit))
        var descriptor = FetchDescriptor<CatalogueItem>(predicate: #Predicate { wanted.contains($0.persistentModelID) })
        descriptor.relationshipKeyPathsForPrefetching = [\.storedFieldValues]
        let fetched = (try? context.fetch(descriptor)) ?? []
        let byID = Dictionary(fetched.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        items = wanted.compactMap { byID[$0] }
    }
}

// MARK: - Export Request

/// A composer to open for several items: from select mode, or the toolbar.
struct ExportRequest: Identifiable {
    let id = UUID()
    let export: ExportItems
    let format: ExportFormat
    let filters: ExportFilters?
}
