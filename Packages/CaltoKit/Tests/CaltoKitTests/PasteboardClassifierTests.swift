import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CaltoKit

struct PasteboardClassifierTests {
    private let png = Data("png".utf8)
    private let tiff = Data("tiff".utf8)

    private func entry(_ type: UTType, _ data: Data) -> PasteboardEntry {
        PasteboardEntry(typeIdentifier: type.identifier, data: data)
    }

    private func text(_ string: String) -> PasteboardEntry {
        entry(.utf8PlainText, Data(string.utf8))
    }

    private func fileURL(_ path: String) -> PasteboardEntry {
        entry(.fileURL, URL(filePath: path).dataRepresentation)
    }

    @Test("Nothing on the pasteboard")
    func empty() {
        #expect(PasteboardClassifier.classify([]) == .empty)
        #expect(PasteboardClassifier.classify([[]]) == .empty)
    }

    @Test("A screenshot prefers PNG over TIFF")
    func screenshot() {
        let item = [entry(.tiff, tiff), entry(.png, png)]
        #expect(PasteboardClassifier.classify([item]) == .images([png]))
    }

    @Test("An image wins over text in the same item (image copied from a browser)")
    func imageBeatsText() {
        let item = [text("alt text"), entry(.tiff, tiff)]
        #expect(PasteboardClassifier.classify([item]) == .images([tiff]))
    }

    @Test("Other image formats are accepted via UTType conformance")
    func otherImageFormat() {
        let gif = Data("gif".utf8)
        #expect(PasteboardClassifier.classify([[entry(.gif, gif)]]) == .images([gif]))
    }

    @Test("Several copied images become several attachments")
    func multipleImages() {
        #expect(PasteboardClassifier.classify([[entry(.png, png)], [entry(.tiff, tiff)]]) == .images([png, tiff]))
    }

    @Test("Plain text is trimmed")
    func plainText() {
        #expect(PasteboardClassifier.classify([[text("  Dinner Friday 19:00 \n")]]) == .text("Dinner Friday 19:00"))
    }

    @Test("Whitespace-only text is unsupported")
    func blankText() {
        #expect(PasteboardClassifier.classify([[text(" \n\t ")]]) == .unsupported)
    }

    @Test("Image files copied in Finder are used instead of their icons")
    func imageFilesBeatIcons() {
        let item = [fileURL("/Users/me/Desktop/Poster.JPG"), entry(.tiff, tiff), text("Poster.JPG")]
        #expect(PasteboardClassifier.classify([item]) == .imageFiles([URL(filePath: "/Users/me/Desktop/Poster.JPG")]))
    }

    @Test("Non-image files are unsupported, not their icons")
    func nonImageFile() {
        let item = [fileURL("/Users/me/report.pdf"), entry(.tiff, tiff)]
        #expect(PasteboardClassifier.classify([item]) == .unsupported)
    }

    @Test("Unknown types are unsupported")
    func unknownType() {
        let item = [PasteboardEntry(typeIdentifier: "com.example.private", data: Data([1, 2, 3]))]
        #expect(PasteboardClassifier.classify([item]) == .unsupported)
    }
}
