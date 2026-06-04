//
//  ThumbnailLoader.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 12/04/2026.
//

import SwiftData
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Thumbnail Loader

/// Reads and decodes item cover thumbnails on a background thread.
///
/// Uses a dedicated ModelContext (via @ModelActor) so the main thread never blocks
/// on .externalStorage blob reads or UIImage decoding. Initialised once at app startup
/// with the shared ModelContainer; views call it via ThumbnailLoader.shared.
@ModelActor
final actor ThumbnailLoader {
    // nonisolated(unsafe): safe because `shared` is written once at app startup
    // (in catalogue_itApp.init) before any view accesses it.
    nonisolated(unsafe) static var shared: ThumbnailLoader?

#if os(iOS)
    /// Returns a thumbnail UIImage for the item, on this actor's background thread.
    /// Fast path: reads pre-generated coverThumbnailData (items added/edited in-app).
    /// Fallback: fetches only the cover photo via a targeted query, generates the thumbnail,
    /// and writes it back to coverThumbnailData so subsequent calls use the fast path.
    func thumbnail(for itemID: PersistentIdentifier) -> UIImage? {
        guard let item = self[itemID, as: CatalogueItem.self] else { return nil }
        guard let data = coverThumbnailData(for: item) else { return nil }
        return UIImage(data: data)
    }
#else
    func thumbnail(for itemID: PersistentIdentifier) -> NSImage? {
        guard let item = self[itemID, as: CatalogueItem.self] else { return nil }
        guard let data = coverThumbnailData(for: item) else { return nil }
        return NSImage(data: data)
    }
#endif

    // MARK: - Private

    private func coverThumbnailData(for item: CatalogueItem) -> Data? {
        if let data = item.coverThumbnailData { return data }

        // Fallback: load only the single lowest-priority photo rather than faulting
        // in the entire photos relationship just to call .min() on it.
        let coverItemID = item.persistentModelID
        var descriptor = FetchDescriptor<ItemPhoto>(
            predicate: #Predicate { $0.item?.persistentModelID == coverItemID },
            sortBy: [SortDescriptor(\.priority)]
        )
        descriptor.fetchLimit = 1
        guard let coverPhoto = try? modelContext.fetch(descriptor).first,
              let thumbData = makeThumbnailData(from: coverPhoto.imageData) else { return nil }

        // Cache so this fallback is never needed again for this item.
        item.coverThumbnailData = thumbData
        try? modelContext.save()
        return thumbData
    }
}
