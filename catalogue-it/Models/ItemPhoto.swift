//
//  ItemPhoto.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData

// MARK: - Item Photo

/// A photo attached to an item
@Model
final class ItemPhoto {
    @Attribute(.externalStorage) var imageData: Data
    @Attribute(.externalStorage) var thumbnailData: Data?
    var priority: Int
    var caption: String?

    var item: CatalogueItem?

    init(imageData: Data, thumbnailData: Data? = nil, priority: Int = 0, caption: String? = nil) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.priority = priority
        self.caption = caption
    }
}
