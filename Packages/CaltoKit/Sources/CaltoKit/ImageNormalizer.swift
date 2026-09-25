import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares images for sending to a model: applies EXIF orientation, downscales,
/// and re-encodes from pixels only, so EXIF/GPS and other metadata never leave the Mac.
public enum ImageNormalizer {
    /// Longest side after downscaling; enough for legible screenshots, within every provider's limits.
    public static let maxPixelSize = 2048
    /// PNG keeps text in screenshots crisp; larger results fall back to JPEG.
    public static let maxPNGBytes = 4 * 1024 * 1024
    static let jpegQuality = 0.85

    public static func normalize(_ data: Data) throws(InputError) -> ImageAttachment {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else {
            throw .unreadableImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw .unreadableImage
        }

        if let png = encode(image, as: .png), png.count <= maxPNGBytes {
            return ImageAttachment(data: png, contentType: .png, pixelWidth: image.width, pixelHeight: image.height)
        }
        guard let jpeg = encode(image, as: .jpeg, quality: jpegQuality) else {
            throw .unreadableImage
        }
        return ImageAttachment(data: jpeg, contentType: .jpeg, pixelWidth: image.width, pixelHeight: image.height)
    }

    static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }
}
