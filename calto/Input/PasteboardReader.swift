import AppKit
import CaltoKit
import UniformTypeIdentifiers

/// Reads only the representations calto can use and hands them to `PasteboardClassifier`.
enum PasteboardReader {
    static func read(_ pasteboard: NSPasteboard = .general) -> PasteboardContent {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.filter(isRelevant).compactMap { type in
                item.data(forType: type).map { PasteboardEntry(typeIdentifier: type.rawValue, data: $0) }
            }
        }
        return PasteboardClassifier.classify(items)
    }

    private static func isRelevant(_ type: NSPasteboard.PasteboardType) -> Bool {
        type == .fileURL || type == .string || (UTType(type.rawValue)?.conforms(to: .image) ?? false)
    }
}
