//
//  ImageHelpersTests.swift
//  UnitTests
//

import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import catalogue_it

// MARK: - Image Helpers Tests

/// Tests thumbnail generation and JPEG compression against programmatically
/// generated PNG data, so no bundled fixtures are needed.
@MainActor
struct ImageHelpersTests {

    // MARK: - Fixtures

    /// Creates solid-colour PNG data of the given pixel size.
    private func makePNGData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let output = try #require(CFDataCreateMutable(kCFAllocatorDefault, 0))
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// Decodes the pixel dimensions of encoded image data.
    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    // MARK: - makeThumbnailData (ImageIO)

    @Test("Large images are downscaled to the max dimension, preserving aspect ratio")
    func thumbnailDownscalesLargeImage() throws {
        let source = try makePNGData(width: 600, height: 400)
        let thumb = try #require(makeThumbnailData(from: source, maxDimension: 300))
        let size = try pixelSize(of: thumb)
        #expect(max(size.width, size.height) <= 300)
        #expect(size.width > size.height, "Landscape aspect ratio should be preserved")
    }

    @Test("Thumbnail output is JPEG data")
    func thumbnailOutputIsJPEG() throws {
        let source = try makePNGData(width: 400, height: 400)
        let thumb = try #require(makeThumbnailData(from: source))
        #expect(thumb.prefix(2) == Data([0xFF, 0xD8]), "JPEG data starts with the FF D8 marker")
    }

    @Test("Invalid image data produces no thumbnail")
    func thumbnailFromGarbageIsNil() {
        #expect(makeThumbnailData(from: Data("not an image".utf8)) == nil)
        #expect(makeThumbnailData(from: Data()) == nil)
    }

    // MARK: - Data.makeThumbnail (platform image APIs)

    @Test("makeThumbnail returns decodable image data for a valid source")
    func dataMakeThumbnail() throws {
        let source = try makePNGData(width: 600, height: 400)
        let thumb = try #require(source.makeThumbnail(maxDimension: 300))
        let size = try pixelSize(of: thumb)
        #expect(size.width > 0)
        #expect(size.height > 0)
    }

    @Test("makeThumbnail returns nil for invalid data")
    func dataMakeThumbnailFromGarbageIsNil() {
        #expect(Data("not an image".utf8).makeThumbnail() == nil)
    }

    // MARK: - Data.compressedAsJPEG

    @Test("compressedAsJPEG converts PNG data to JPEG")
    func compressedAsJPEG() throws {
        let source = try makePNGData(width: 200, height: 200)
        let jpeg = try #require(source.compressedAsJPEG(quality: 0.8))
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test("compressedAsJPEG returns nil for invalid data")
    func compressedAsJPEGFromGarbageIsNil() {
        #expect(Data("not an image".utf8).compressedAsJPEG() == nil)
    }

    // MARK: - Data.asImage

    @Test("asImage decodes valid image data and rejects garbage")
    func asImage() throws {
        let source = try makePNGData(width: 10, height: 10)
        #expect(source.asImage() != nil)
        #expect(Data("not an image".utf8).asImage() == nil)
    }
}
