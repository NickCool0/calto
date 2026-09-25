import Foundation
import UniformTypeIdentifiers

/// One representation of a pasteboard item, e.g. `public.png` and its bytes.
public struct PasteboardEntry: Sendable, Hashable {
    public var typeIdentifier: String
    public var data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}

/// What a paste should add to the input.
public enum PasteboardContent: Sendable, Equatable {
    /// Image files copied in Finder. They must be read by the app (sandbox permitting).
    case imageFiles([URL])
    /// Image bytes, one per pasteboard item (screenshots, images copied from a browser).
    case images([Data])
    case text(String)
    /// Something calto can't use: non-image files, rich content without plain text…
    case unsupported
    case empty
}

/// How ⌘V in the input field should be handled, decided from the pasteboard's types alone
/// (reading types never counts as reading the user's data).
public enum PasteKind: Sendable, Equatable {
    /// Let the text view paste text as usual.
    case text
    /// Image bytes: add them as attachments.
    case images
    /// Files copied in Finder: image files become attachments, anything else is pasted as text.
    case files
}

/// Decides what a paste means, independently of AppKit so the rules are unit-testable.
public enum PasteboardClassifier {
    /// Plain text wins over images: apps like Numbers, Excel or Word put a picture of the selection
    /// next to the copied text, and the text is what the user means. Screenshots and "Copy Image"
    /// carry no plain text.
    public static func pasteKind(forTypes types: [String]) -> PasteKind {
        if types.contains(fileURLType) {
            return .files
        }
        if types.contains(where: isPlainText) {
            return .text
        }
        if types.contains(where: { UTType($0)?.conforms(to: .image) ?? false }) {
            return .images
        }
        return .text
    }

    static func isPlainText(_ type: String) -> Bool {
        type == plainTextType || type == UTType.plainText.identifier || type == "NSStringPboardType"
    }

    static let fileURLType = UTType.fileURL.identifier
    static let plainTextType = UTType.utf8PlainText.identifier
    /// Lossless and screenshot formats first, so the best representation of an item wins.
    static let preferredImageTypes: [UTType] = [.png, .tiff, .heic, .jpeg]

    /// - Parameter items: pasteboard items, each with its representations in the pasteboard's order.
    public static func classify(_ items: [[PasteboardEntry]]) -> PasteboardContent {
        let entries = items.flatMap { $0 }
        guard !entries.isEmpty else { return .empty }

        // Finder puts file URLs *and* the file icon on the pasteboard; the file itself is what matters.
        let fileURLs = entries
            .filter { $0.typeIdentifier == fileURLType }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil) }
        if !fileURLs.isEmpty {
            let imageURLs = fileURLs.filter(isImageFile)
            return imageURLs.isEmpty ? .unsupported : .imageFiles(imageURLs)
        }

        let images = items.compactMap(bestImage)
        if !images.isEmpty {
            return .images(images)
        }

        let text = entries
            .first { $0.typeIdentifier == plainTextType }
            .flatMap { String(data: $0.data, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty {
            return .text(text)
        }
        return .unsupported
    }

    static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image) ?? false
    }

    static func bestImage(in item: [PasteboardEntry]) -> Data? {
        for type in preferredImageTypes {
            if let entry = item.first(where: { $0.typeIdentifier == type.identifier }) {
                return entry.data
            }
        }
        return item.first { UTType($0.typeIdentifier)?.conforms(to: .image) ?? false }?.data
    }
}
