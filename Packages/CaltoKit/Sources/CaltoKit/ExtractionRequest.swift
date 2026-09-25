import Foundation

/// Everything a provider needs to extract events. The user's current date, time zone and locale
/// travel with every request so relative dates ("tomorrow", "on Thursday") resolve correctly.
public struct ExtractionRequest: Sendable, Hashable {
    /// `nil` when the input consists of images only.
    public var text: String?
    public var images: [ImageAttachment]
    /// The optional user instruction ("only meetings with Anna", "remind me an hour before").
    public var instruction: String?
    public var referenceDate: Date
    public var timeZone: TimeZone
    public var locale: Locale

    public init(
        content: InputContent,
        instruction: String,
        referenceDate: Date = .now,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) throws(InputError) {
        guard !content.isEmpty else {
            throw .emptyInput
        }
        let text = content.trimmedText
        guard text.count <= InputContent.maxTextLength else {
            throw .textTooLong(limit: InputContent.maxTextLength)
        }
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)

        self.text = text.isEmpty ? nil : text
        self.images = content.images
        self.instruction = instruction.isEmpty ? nil : instruction
        self.referenceDate = referenceDate
        self.timeZone = timeZone
        self.locale = locale
    }
}
