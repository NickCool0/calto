import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CaltoKit

struct InputContentTests {
    private func image() -> ImageAttachment {
        ImageAttachment(data: Data([0]), contentType: .png, pixelWidth: 1, pixelHeight: 1)
    }

    @Test("At most five images")
    func imageLimit() throws {
        var content = InputContent()
        for _ in 0..<InputContent.maxImages {
            try content.add(image())
        }
        #expect(throws: InputError.tooManyImages(limit: 5)) {
            try content.add(image())
        }
        #expect(content.images.count == 5)
    }

    @Test("Removing an image by id")
    func removeImage() throws {
        var content = InputContent()
        let first = image()
        try content.add(first)
        try content.add(image())
        content.removeImage(id: first.id)
        #expect(content.images.count == 1)
        #expect(!content.images.contains(first))
    }

    @Test("Appended text is separated by a blank line; blank fragments are ignored")
    func appendText() {
        var content = InputContent()
        content.appendText("  Standup 10:00 ")
        content.appendText("\n")
        content.appendText("Lunch 13:00")
        #expect(content.text == "Standup 10:00\n\nLunch 13:00")
    }

    @Test("Whitespace-only content counts as empty")
    func emptiness() throws {
        #expect(InputContent(text: " \n ").isEmpty)
        var content = InputContent()
        try content.add(image())
        #expect(!content.isEmpty)
    }
}

struct ExtractionRequestTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private let zone = TimeZone(identifier: "Europe/Moscow")!
    private let locale = Locale(identifier: "ru_RU")

    @Test("Carries trimmed text (with any instructions in it) and the user's date context")
    func buildsRequest() throws {
        let request = try ExtractionRequest(
            content: InputContent(text: "  Кино в четверг в 19:30, напомни за час \n"),
            referenceDate: date, timeZone: zone, locale: locale
        )
        #expect(request.text == "Кино в четверг в 19:30, напомни за час")
        #expect(request.images.isEmpty)
        #expect(request.referenceDate == date)
        #expect(request.timeZone == zone)
        #expect(request.locale == locale)
    }

    @Test("Image-only input has no text")
    func imageOnly() throws {
        var content = InputContent()
        try content.add(ImageAttachment(data: Data([0]), contentType: .png, pixelWidth: 1, pixelHeight: 1))
        let request = try ExtractionRequest(content: content)
        #expect(request.text == nil)
        #expect(request.images.count == 1)
    }

    @Test("Empty input is rejected")
    func rejectsEmpty() {
        #expect(throws: InputError.emptyInput) {
            try ExtractionRequest(content: InputContent(text: "   "))
        }
    }

    @Test("Overlong text is rejected")
    func rejectsLongText() {
        let text = String(repeating: "a", count: InputContent.maxTextLength + 1)
        #expect(throws: InputError.textTooLong(limit: InputContent.maxTextLength)) {
            try ExtractionRequest(content: InputContent(text: text))
        }
    }
}
