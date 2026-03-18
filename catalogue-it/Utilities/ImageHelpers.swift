//
//  ImageHelpers.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Data + Image

extension Data {
    /// Creates a SwiftUI Image from raw image data, or nil if the data is not a valid image.
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

    /// Compresses image data to JPEG at the given quality (0–1), cross-platform.
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
