//
//  ThumbnailHelpers.swift
//  catalogue-it
//

import Foundation
import ImageIO

// MARK: - Thumbnail Generation

/// Thread-safe: ImageIO has no main-thread requirement.
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

/// The centre square of an image, `pixelSize` on a side, as JPEG. Never upscales.
nonisolated func makeSquareIconData(from data: Data, pixelSize: Int = CatalogueIcon.photoPixelSize) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0 else { return nil }

    // Sized so the short side lands on `pixelSize`; the crop then takes the centre.
    let longSide = max(width, height)
    let shortSide = min(width, height)
    let maxPixelSize = min(longSide, Int((Double(pixelSize) * Double(longSide) / Double(shortSide)).rounded(.up)))
    let thumbOptions: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }

    let side = min(scaled.width, scaled.height)
    let crop = CGRect(x: (scaled.width - side) / 2, y: (scaled.height - side) / 2, width: side, height: side)
    guard let square = scaled.cropping(to: crop),
          let output = CFDataCreateMutable(kCFAllocatorDefault, 0),
          let dest = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, square, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return output as Data
}
