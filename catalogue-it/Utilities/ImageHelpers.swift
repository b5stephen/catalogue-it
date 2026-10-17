//
//  ImageHelpers.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Data + Image

extension Data {
    func asImage() -> Image? {
#if os(iOS)
        guard let uiImage = UIImage(data: self) else { return nil }
        return Image(uiImage: uiImage)
#elseif os(macOS)
        guard let nsImage = NSImage(data: self) else { return nil }
        return Image(nsImage: nsImage)
#else
        return nil
#endif
    }

    /// JPEG at 0.7 within a `maxDimension` square. Never upscales.
    func makeThumbnail(maxDimension: CGFloat = 300) -> Data? {
#if os(iOS)
        guard let source = UIImage(data: self) else { return nil }
        let size = source.size
        let scale = Swift.min(Swift.min(maxDimension / size.width, maxDimension / size.height), 1.0)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let thumb = renderer.image { _ in source.draw(in: CGRect(origin: .zero, size: targetSize)) }
        return thumb.jpegData(compressionQuality: 0.7)
#elseif os(macOS)
        guard let source = NSImage(data: self) else { return nil }
        let size = source.size
        let scale = Swift.min(Swift.min(maxDimension / size.width, maxDimension / size.height), 1.0)
        let targetSize = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: targetSize)
        thumb.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: targetSize))
        thumb.unlockFocus()
        var proposedRect = NSRect(origin: .zero, size: targetSize)
        guard let cgImage = thumb.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.7])
#else
        return nil
#endif
    }

    func compressedAsJPEG(quality: CGFloat = 0.8) -> Data? {
#if os(iOS)
        UIImage(data: self)?.jpegData(compressionQuality: quality)
#elseif os(macOS)
        guard let nsImage = NSImage(data: self),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
#else
        nil
#endif
    }
}
