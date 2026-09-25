import Foundation

/// Everything a provider needs to extract events. The user's current date, time zone and locale
/// travel with every request so relative dates ("tomorrow", "on Thursday") resolve correctly.
public struct ExtractionRequest: Sendable, Hashable {
    /// What the user typed: the event details and, possibly, instructions in the same text
    /// ("only meetings with Anna", "remind me an hour before"). `nil` when the input is images only.
    public var text: String?
    public var images: [ImageAttachment]
    /// The user's standing instructions from Settings, added to every request.
    public var customInstructions: String?
    public var referenceDate: Date
    public var timeZone: TimeZone
    public var locale: Locale

    public init(
        content: InputContent,
        customInstructions: String = "",
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
        let customInstructions = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)

        self.text = text.isEmpty ? nil : text
        self.images = content.images
        self.customInstructions = customInstructions.isEmpty ? nil : customInstructions
        self.referenceDate = referenceDate
        self.timeZone = timeZone
        self.locale = locale
    }
}
