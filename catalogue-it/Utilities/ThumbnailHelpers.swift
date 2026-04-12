//
//  ThumbnailHelpers.swift
//  catalogue-it
//

import Foundation
import ImageIO

// MARK: - Thumbnail Generation

/// Generates JPEG thumbnail data from image data using ImageIO.
/// Thread-safe — ImageIO has no main-thread requirement.
nonisolated func makeThumbnailData(from data: Data, maxDimension: Int = 300) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let thumbOptions: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
    guard let output = CFDataCreateMutable(kCFAllocatorDefault, 0),
          let dest = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return output as Data
}
