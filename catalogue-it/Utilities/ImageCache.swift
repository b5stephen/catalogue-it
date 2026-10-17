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

actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, PlatformImage>()

    func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: PlatformImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    func removeImage(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    /// For CloudKit merges: entries are keyed by item, and a remotely replaced photo reuses the key.
    func removeAll() {
        cache.removeAllObjects()
    }
}
