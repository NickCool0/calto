import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CaltoKit

struct ImageNormalizerTests {
    /// Draws an opaque image; `noise` makes it incompressible so PNG exceeds the size limit.
    private func makeImage(width: Int, height: Int, noise: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        if noise, let pixels = context.data?.assumingMemoryBound(to: UInt32.self) {
            var seed: UInt32 = 0x1234_5678
            for index in 0..<(context.bytesPerRow / 4 * height) {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                pixels[index] = seed
            }
        } else {
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(context.makeImage())
    }

    private func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test("Large images are downscaled to 2048 px on the long side, keeping the aspect ratio")
    func downscales() throws {
        let data = try encode(makeImage(width: 4000, height: 3000), as: .png)
        let attachment = try ImageNormalizer.normalize(data)
        #expect(attachment.pixelWidth == 2048)
        #expect(attachment.pixelHeight == 1536)
        #expect(attachment.contentType == .png)
    }

    @Test("Small images are not enlarged")
    func keepsSmallImages() throws {
        let data = try encode(makeImage(width: 640, height: 480), as: .png)
        let attachment = try ImageNormalizer.normalize(data)
        #expect(attachment.pixelWidth == 640)
        #expect(attachment.pixelHeight == 480)
    }

    @Test("GPS and EXIF metadata are stripped")
    func stripsMetadata() throws {
        let metadata: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 55.75, kCGImagePropertyGPSLongitude: 37.61],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret"],
        ]
        let data = try encode(makeImage(width: 800, height: 600), as: .jpeg, properties: metadata)
        #expect(try properties(of: data)[kCGImagePropertyGPSDictionary] != nil)

        let attachment = try ImageNormalizer.normalize(data)
        let output = try properties(of: attachment.data)
        #expect(output[kCGImagePropertyGPSDictionary] == nil)
        let exif = output[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifUserComment] == nil)
    }

    @Test("Images too large as PNG fall back to JPEG")
    func jpegFallback() throws {
        let data = try encode(makeImage(width: 2048, height: 2048, noise: true), as: .png)
        #expect(data.count > ImageNormalizer.maxPNGBytes)
        let attachment = try ImageNormalizer.normalize(data)
        #expect(attachment.contentType == .jpeg)
    }

    @Test("Garbage data is reported as an unreadable image")
    func rejectsGarbage() {
        #expect(throws: InputError.unreadableImage) {
            try ImageNormalizer.normalize(Data("not an image".utf8))
        }
    }
}
