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

/// The cold path deliberately skips a shared actor: each row decodes in its own detached task
/// and context, so visible rows load in parallel. Set `container` at startup.
enum ThumbnailLoader {
    // nonisolated(unsafe): written once at startup, before any view reads it.
    nonisolated(unsafe) static var container: ModelContainer?

    // MARK: - Filesystem Cache

    /// In Caches: the OS may evict it, and thumbnails are regenerable from the photos.
    nonisolated static func thumbnailCacheURL(for itemID: PersistentIdentifier) -> URL? {
        guard let encoded = try? JSONEncoder().encode(itemID) else { return nil }
        // Base64url, so the name is filesystem-safe everywhere.
        let filename = encoded.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("thumbnails/\(filename).jpg")
    }

    /// Keys are `PersistentIdentifier`s, stable across a remote edit, so a photo replaced
    /// elsewhere can't be spotted by key. Regeneration is lazy and per row, so dropping the lot
    /// is cheap.
    nonisolated static func clearDiskCache() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("thumbnails"))
    }

    nonisolated static func writeThumbnailToCache(_ data: Data, for itemID: PersistentIdentifier) {
        guard let fileURL = thumbnailCacheURL(for: itemID) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }
}
