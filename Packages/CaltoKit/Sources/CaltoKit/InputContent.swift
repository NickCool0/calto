import Foundation
import UniformTypeIdentifiers

/// An image prepared for recognition: downscaled and re-encoded without metadata.
public struct ImageAttachment: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let data: Data
    /// `.png` or `.jpeg`.
    public let contentType: UTType
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(id: UUID = UUID(), data: Data, contentType: UTType, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// What the user has pasted, dropped or typed into the input window.
public struct InputContent: Sendable, Hashable {
    public static let maxImages = 5
    public static let maxTextLength = 50_000

    /// Editable in the input window; pasted and dropped text is appended here.
    public var text: String
    public private(set) var images: [ImageAttachment]

    public init(text: String = "", images: [ImageAttachment] = []) {
        self.text = text
        self.images = images
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isEmpty: Bool {
        trimmedText.isEmpty && images.isEmpty
    }

    public mutating func add(_ image: ImageAttachment) throws(InputError) {
        guard images.count < Self.maxImages else {
            throw .tooManyImages(limit: Self.maxImages)
        }
        images.append(image)
    }

    public mutating func removeImage(id: ImageAttachment.ID) {
        images.removeAll { $0.id == id }
    }

    /// Appends a pasted or dropped fragment, separated from existing text by a blank line.
    public mutating func appendText(_ fragment: String) {
        let fragment = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return }
        text = trimmedText.isEmpty ? fragment : trimmedText + "\n\n" + fragment
    }
}

public enum InputError: Error, Equatable, Sendable {
    case emptyInput
    case tooManyImages(limit: Int)
    case textTooLong(limit: Int)
    case unreadableImage
    case unsupportedContent
}
