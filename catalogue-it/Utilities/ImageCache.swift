//
//  ImageCache.swift
//  catalogue-it
//

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif

// MARK: - Image Cache

/// Shared, memory-pressure-aware cache for decoded thumbnail images.
/// NSCache automatically evicts entries when the system is under memory pressure.
actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, PlatformImage>()

    func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: PlatformImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
