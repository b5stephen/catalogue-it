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

/// Static utilities for item cover thumbnail caching.
///
/// The cold-path (DB fetch + decode) is intentionally NOT routed through a shared actor.
/// Each row creates an ephemeral ModelContext in its own Task.detached so all visible rows
/// fetch and decode in parallel — no serialisation through a single actor queue.
///
/// Set `container` once at app startup before any view accesses these utilities.
enum ThumbnailLoader {
    // nonisolated(unsafe): written once at app startup (catalogue_itApp.init) before any
    // view accesses it.
    nonisolated(unsafe) static var container: ModelContainer?

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
    nonisolated static func writeThumbnailToCache(_ data: Data, for itemID: PersistentIdentifier) {
        guard let fileURL = thumbnailCacheURL(for: itemID) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }
}
