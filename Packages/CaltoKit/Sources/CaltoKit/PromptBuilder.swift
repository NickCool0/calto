import Foundation

/// The two halves of a prompt: stable rules (system) and this request's content (user).
public struct ExtractionPrompt: Sendable, Hashable {
    public var system: String
    public var user: String

    public init(system: String, user: String) {
        self.system = system
        self.user = user
    }
}

public enum PromptBuilder {
    static let rules = """
    You extract calendar events from the user's text and images (screenshots of invitations, chats, \
    posters, schedules, tickets).

    Rules:
    - Return every distinct event the user would want in their calendar. If there is none, return an empty list.
    - Resolve relative dates ("today", "tomorrow", "on Thursday", "next week", "in 3 days") from the current \
    date, weekday and time zone given in the request.
    - Write start and end as local wall-clock times: YYYY-MM-DDTHH:MM. For all-day events use YYYY-MM-DD and set \
    all_day to true; their end is the last day, or null for a single day.
    - Set time_zone only when the source explicitly names a time zone or a city whose time applies; otherwise \
    null, and the times are in the user's time zone.
    - If the end or duration is not stated, set end to null. Do not invent a duration.
    - Never guess silently. If the year is missing and not obvious, the day/month order is unclear, AM/PM is \
    unclear, or anything else is uncertain, make your best guess AND add a short note to ambiguities, written \
    in the user's language.
    - reminder_minutes_before: only when reminders are explicitly requested ("remind me an hour before" → [60]); \
    otherwise null.
    - recurrence: only when repetition is explicitly stated ("every Monday", "daily until June"); otherwise null.
    - url: an online meeting link (Zoom, Google Meet, Teams, …) or the event's page, if present.
    - title: short and specific, in the language of the source text. Put other useful details (agenda, dress \
    code, phone numbers) into notes.
    - Follow the user's instructions, for example to keep only some of the events or to add reminders.
    """

    /// - Parameters:
    ///   - recognizedText: text read from the images on the device (OCR), when the images are not sent.
    ///   - imageCount: images attached to the request itself.
    ///   - includeSchema: spell out the JSON Schema, for endpoints without structured-output support.
    public static func build(
        for request: ExtractionRequest,
        recognizedText: [String] = [],
        imageCount: Int = 0,
        includeSchema: Bool = false
    ) -> ExtractionPrompt {
        var system = rules
        if includeSchema {
            system += "\n\nRespond with only a JSON object that matches this JSON Schema, without any other text:\n"
            system += ExtractionSchema.jsonSchema.jsonString
        }

        var sections = [context(for: request)]
        if let custom = request.customInstructions {
            sections.append("The user's standing instructions:\n\(custom)")
        }
        if let instruction = request.instruction {
            sections.append("Instruction for this request:\n\(instruction)")
        }
        if let text = request.text {
            sections.append("Text:\n\"\"\"\n\(text)\n\"\"\"")
        }
        for (index, text) in recognizedText.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmed.isEmpty ? "(no text found)" : trimmed
            sections.append("Text recognized on image \(index + 1):\n\"\"\"\n\(body)\n\"\"\"")
        }
        if imageCount > 0 {
            sections.append(imageCount == 1 ? "1 image is attached." : "\(imageCount) images are attached.")
        }
        return ExtractionPrompt(system: system, user: sections.joined(separator: "\n\n"))
    }

    /// "Current date and time: 2026-09-25 14:30, Friday. Time zone: Europe/Moscow (UTC+03:00). Locale: ru_RU."
    static func context(for request: ExtractionRequest) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = request.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm, EEEE"
        let now = formatter.string(from: request.referenceDate)

        let seconds = request.timeZone.secondsFromGMT(for: request.referenceDate)
        let sign = seconds < 0 ? "-" : "+"
        let offset = String(format: "UTC%@%02d:%02d", sign, abs(seconds) / 3600, abs(seconds) % 3600 / 60)
        let language = request.locale.language.languageCode?.identifier ?? request.locale.identifier

        return """
        Current date and time: \(now).
        Time zone: \(request.timeZone.identifier) (\(offset)).
        User's locale: \(request.locale.identifier) (write ambiguities in language "\(language)").
        """
    }
}
