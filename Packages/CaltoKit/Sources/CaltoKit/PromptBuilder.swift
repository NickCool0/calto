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
    You turn what the user gives you into calendar events. The input can have two kinds of sources, and \
    you must use ALL of them:
    1. Text the user typed (Source 1). It is the most important source and it wins over images when they \
    disagree ("the screenshot says 18:00 but I'll come at 19" → 19:00).
    2. Images (screenshots of chats, invitations, posters, tickets, schedules), attached or given as text read \
    from them on the user's Mac.
    The typed text and the images usually describe the same event: combine them. The typed text often holds \
    the most important facts (an identifier, a link, a name, what to do) even when it is short.

    How to work:
    - First fill `analysis`: list every fact from the typed text in typed_text_facts, every relevant fact from \
    the images in image_facts, and every URL from both in links. Then write the events from that list, so \
    nothing from either source is lost.
    - The typed text mixes instructions to you with facts. Instructions ("make a task for Monday at 10", \
    "remind me an hour before", "only the meetings with Anna", "every Monday") set fields: date, time, \
    reminders, recurrence, which events to keep. Everything else in the typed text — names and identifiers \
    (servers, databases, tickets, orders), people, numbers, amounts, addresses, what needs to be done, \
    context — is a fact and goes into the event. Never treat the whole typed text as an instruction.
    - Return every distinct event the user would want. If there is none, return an empty list.

    Fields:
    - title: short and specific, in the language of the sources; say what the event is about \
    ("Delete database mesh-sch-pgsql-cl1", not "Task").
    - start / end: local wall-clock time YYYY-MM-DDTHH:MM; all-day events use YYYY-MM-DD with all_day true and \
    their end is the last day (null for one day). Resolve relative dates ("today", "tomorrow", "on Monday", \
    "next week", "in 3 days") from the current date, weekday and time zone in the request. If the end or \
    duration is not stated, end is null; don't invent one and don't report it as an ambiguity.
    - time_zone: only when a source names a time zone or a city whose time applies; otherwise null.
    - location: a place or address. An online call is not a location: its link goes to url and links.
    - notes: all the facts for this event that the title, time and location don't already say, copied \
    verbatim, not summarized, in short paragraphs. Include facts from the typed text AND from the images. \
    Leave out only the pure instructions to you.
    - links: every URL that belongs to the event, from the typed text and the images, each with a short label \
    in the user's language ("Telegram message", "Zoom call", "Ticket", "Booking"). url: the main one of them.
    - quotes: up to 3 short verbatim quotes from a chat or message that explain the event (who asked, the \
    exact task); empty when there is nothing worth quoting.
    - reminder_minutes_before: only when reminders are asked for, one number per reminder \
    ("remind me an hour before" → [60]; "remind me 15 and 30 minutes before" → [15, 30]; \
    "напомни за день и за час" → [1440, 60]). Otherwise null: the user's default reminder is used.
    - recurrence: only when repetition is stated ("every Monday", "daily until June"); otherwise null.
    - ambiguities: never guess silently. If the year, the day/month order, AM/PM or anything else is unclear, \
    make your best guess and add a short note in the user's language. A missing year that is clearly the \
    current or next occurrence is not an ambiguity.

    Typical inputs and what to keep:
    - Work tasks from Telegram or Slack (a message, a screenshot of one, "make a task for …"): the task itself, \
    system/server/database/ticket names and numbers, who asked, and the link to the message or ticket.
    - Meetings and calls: the call link (Zoom, Meet, Teams), meeting ID and passcode, organizer and \
    participants, agenda, the time zone if stated.
    - Posters, tickets, bookings, appointments: venue and address, booking or order number, seat/row/gate, \
    what to bring, doors or check-in time, the link to the ticket or page.
    - Schedules (classes, shifts, conference programs): one event per item, each with its own details, \
    room and speaker; repetition only if stated.

    Never lose a link: every URL from the typed text and from the images must appear in links of at least one \
    event (with several events, in the ones it belongs to; if unsure, in each of them).
    The user's standing instructions, if given, apply to every event unless the typed text says otherwise.
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
        if let text = request.text {
            sections.append("Source 1 — text typed by the user (highest priority; use every fact in it):\n\"\"\"\n\(text)\n\"\"\"")
        } else {
            sections.append("Source 1 — the user typed no text.")
        }
        for (index, text) in recognizedText.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmed.isEmpty ? "(no text found)" : trimmed
            sections.append("Source \(index + 2) — text read from image \(index + 1) on the user's Mac:\n\"\"\"\n\(body)\n\"\"\"")
        }
        if imageCount > 0 {
            let list = (1...imageCount).map { "Source \($0 + 1) — image \($0)" }.joined(separator: ", ")
            sections.append("Attached: \(list). Combine them with Source 1.")
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
