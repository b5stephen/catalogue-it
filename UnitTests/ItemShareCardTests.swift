//
//  ItemShareCardTests.swift
//  UnitTests
//

import Testing
import Foundation
import ImageIO
@testable import catalogue_it

// MARK: - Item Share Card Tests

@MainActor
struct ItemShareCardTests {

    @Test("Each shape renders a PNG at its own pixel size", arguments: ItemShareCardShape.allCases)
    func rendersAtShapeSize(shape: ItemShareCardShape) throws {
        let card = ItemShareCard(
            title: "Spitfire",
            status: "Owned",
            rows: (1...30).map { ItemShareText.Entry(label: "Field \($0)", value: "Value \($0)") },
            photo: nil,
            shape: shape,
            icon: CatalogueIcon(iconName: "airplane", imageData: nil, imageKind: nil),
            colorHex: "#007AFF",
            catalogueName: "Planes"
        )
        let data = try #require(ItemShareCardRenderer.pngData(for: card))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == Int(shape.size.width))
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == Int(shape.size.height))
    }
}
