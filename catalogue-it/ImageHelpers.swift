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
}
