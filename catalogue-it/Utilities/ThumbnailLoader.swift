//
//  ThumbnailLoader.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 12/04/2026.
//

import SwiftData
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Thumbnail Loader

/// Reads and decodes item cover thumbnails on a background thread.
///
/// Uses a dedicated ModelContext (via @ModelActor) so the main thread never blocks
/// on blob reads or image decoding. Initialised once at app startup with the shared
/// ModelContainer; views call it via ThumbnailLoader.shared.
///
/// Thumbnails are cached on the filesystem (Caches directory) rather than stored as
/// Data on the CatalogueItem model. This keeps SQLite rows slim so that CatalogueItem
/// fetches in the main context are not burdened with thumbnail bytes that the main
/// context never reads directly.
@ModelActor
final actor ThumbnailLoader {
    // nonisolated(unsafe): safe because `shared` is written once at app startup
    // (in catalogue_itApp.init) before any view accesses it.
    nonisolated(unsafe) static var shared: ThumbnailLoader?

#if os(iOS)
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

    // MARK: - Filesystem Cache

    /// Stable, filesystem-safe URL for an item's cached thumbnail.
    /// Stored in the Caches directory — the OS may evict this on low storage,
    /// but thumbnails are always regenerable from the source photos.
    nonisolated static func thumbnailCacheURL(for itemID: PersistentIdentifier) -> URL? {
        guard let encoded = try? JSONEncoder().encode(itemID) else { return nil }
        // Base64url-encode the JSON so the filename is filesystem-safe on all platforms.
        let filename = encoded.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("thumbnails/\(filename).jpg")
    }

    /// Writes thumbnail data to the filesystem cache, creating the directory if needed.
    /// Safe to call from any isolation context.
    nonisolated static func writeThumbnailToCache(_ data: Data, for itemID: PersistentIdentifier) {
        guard let fileURL = thumbnailCacheURL(for: itemID) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }

    // MARK: - Private

    private func coverThumbnailData(for item: CatalogueItem) -> Data? {
        let itemID = item.persistentModelID

        // 1. Fast path: filesystem cache. No SQLite access, no SwiftData write.
        if let fileURL = Self.thumbnailCacheURL(for: itemID),
           let data = try? Data(contentsOf: fileURL) {
            return data
        }

        // 2. Slow path: load cover photo and generate the thumbnail.
        //    Fetches only the single cover (lowest-priority) photo to avoid faulting
        //    in the entire photos relationship.
        var descriptor = FetchDescriptor<ItemPhoto>(
            predicate: #Predicate { $0.item?.persistentModelID == itemID },
            sortBy: [SortDescriptor(\.priority)]
        )
        descriptor.fetchLimit = 1
        guard let coverPhoto = try? modelContext.fetch(descriptor).first,
              let thumbData = makeThumbnailData(from: coverPhoto.imageData) else { return nil }

        // Persist to filesystem — no SwiftData write, so no merge noise on the main context.
        Self.writeThumbnailToCache(thumbData, for: itemID)
        return thumbData
    }
}
