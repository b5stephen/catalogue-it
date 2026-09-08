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
    // Every stored property below carries a default value: CloudKit rejects
    // non-optional attributes that have none, and the container fails to build.
    @Attribute(.externalStorage) var imageData: Data = Data()
    @Attribute(.externalStorage) var thumbnailData: Data?
    var priority: Int = 0
    var caption: String?

    var item: CatalogueItem?

    init(imageData: Data, thumbnailData: Data? = nil, priority: Int = 0, caption: String? = nil) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.priority = priority
        self.caption = caption
    }
}
