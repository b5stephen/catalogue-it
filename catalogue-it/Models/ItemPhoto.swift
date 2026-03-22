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
    var priority: Int
    var caption: String?

    var item: CatalogueItem?

    init(imageData: Data, priority: Int = 0, caption: String? = nil) {
        self.imageData = imageData
        self.priority = priority
        self.caption = caption
    }
}
