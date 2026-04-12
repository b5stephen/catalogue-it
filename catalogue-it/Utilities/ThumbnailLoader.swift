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
    /// Fallback: generates a thumbnail from the cover photo's imageData on demand
    /// (imported items, where coverThumbnailData was not pre-computed).
    func thumbnail(for itemID: PersistentIdentifier) -> UIImage? {
        guard let item = self[itemID, as: CatalogueItem.self] else { return nil }
        if let data = item.coverThumbnailData {
            return UIImage(data: data)
        }
        guard let photoData = item.photos.min(by: { $0.priority < $1.priority })?.imageData,
              let thumbData = makeThumbnailData(from: photoData) else { return nil }
        return UIImage(data: thumbData)
    }
#else
    func thumbnail(for itemID: PersistentIdentifier) -> NSImage? {
        guard let item = self[itemID, as: CatalogueItem.self] else { return nil }
        if let data = item.coverThumbnailData {
            return NSImage(data: data)
        }
        guard let photoData = item.photos.min(by: { $0.priority < $1.priority })?.imageData,
              let thumbData = makeThumbnailData(from: photoData) else { return nil }
        return NSImage(data: thumbData)
    }
#endif
}
