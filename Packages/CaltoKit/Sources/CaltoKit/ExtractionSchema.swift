import Foundation

/// The structured answer every provider must return, and its JSON Schema.
///
/// Dates are local wall-clock strings so the model never does time-zone arithmetic;
/// `EventResolver` turns them into `Date`s using the user's (or the stated) time zone.
public struct ExtractionResponse: Sendable, Hashable, Codable {
    /// What the model read from each source before writing the events (see `WireAnalysis`).
    public var analysis: WireAnalysis?
    public var events: [WireEvent]

    public init(analysis: WireAnalysis? = nil, events: [WireEvent]) {
        self.analysis = analysis
        self.events = events
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        analysis = try? container.decodeIfPresent(WireAnalysis.self, forKey: .analysis)
        events = try container.decode([WireEvent].self, forKey: .events)
    }
}

/// The model's notes on its sources, written *before* the events (schema keys are ordered
/// alphabetically, and "analysis" sorts first). Listing every fact from the typed text and from each
/// image first keeps weaker models from dropping one of the sources.
public struct WireAnalysis: Sendable, Hashable, Codable {
    public var typedTextFacts: [String]
    public var imageFacts: [String]
    public var links: [String]

    enum CodingKeys: String, CodingKey {
        case links
        case typedTextFacts = "typed_text_facts"
        case imageFacts = "image_facts"
    }

    public init(typedTextFacts: [String] = [], imageFacts: [String] = [], links: [String] = []) {
        self.typedTextFacts = typedTextFacts
        self.imageFacts = imageFacts
        self.links = links
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        typedTextFacts = (try? container.decodeIfPresent([String].self, forKey: .typedTextFacts)) ?? []
        imageFacts = (try? container.decodeIfPresent([String].self, forKey: .imageFacts)) ?? []
        links = (try? container.decodeIfPresent([String].self, forKey: .links)) ?? []
    }
}

/// A link that belongs to an event, with a short human label ("Telegram message", "Zoom").
public struct WireLink: Sendable, Hashable, Codable {
    public var url: String
    public var label: String?

    public init(url: String, label: String? = nil) {
        self.url = url
        self.label = label
    }
}

public struct WireEvent: Sendable, Hashable, Codable {
    public var title: String
    /// `YYYY-MM-DDTHH:MM`, or `YYYY-MM-DD` for all-day events.
    public var start: String
    public var end: String?
    public var allDay: Bool
    public var timeZone: String?
    public var location: String?
    public var url: String?
    public var notes: String?
    /// Every link that belongs to the event; the composer lists them under the notes.
    public var links: [WireLink]
    /// Key quotes from the chat or screenshot, kept as context.
    public var quotes: [String]
    /// `nil` means reminders were not mentioned.
    public var reminderMinutesBefore: [Int]?
    public var recurrence: WireRecurrence?
    public var ambiguities: [String]

    enum CodingKeys: String, CodingKey {
        case title, start, end, location, url, notes, links, quotes, recurrence, ambiguities
        case allDay = "all_day"
        case timeZone = "time_zone"
        case reminderMinutesBefore = "reminder_minutes_before"
    }

    public init(
        title: String,
        start: String,
        end: String? = nil,
        allDay: Bool = false,
        timeZone: String? = nil,
        location: String? = nil,
        url: String? = nil,
        notes: String? = nil,
        links: [WireLink] = [],
        quotes: [String] = [],
        reminderMinutesBefore: [Int]? = nil,
        recurrence: WireRecurrence? = nil,
        ambiguities: [String] = []
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.timeZone = timeZone
        self.location = location
        self.url = url
        self.notes = notes
        self.links = links
        self.quotes = quotes
        self.reminderMinutesBefore = reminderMinutesBefore
        self.recurrence = recurrence
        self.ambiguities = ambiguities
    }

    /// Lenient: models in plain JSON mode sometimes omit optional keys.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        start = try container.decode(String.self, forKey: .start)
        end = try container.decodeIfPresent(String.self, forKey: .end)
        allDay = try container.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        links = (try? container.decodeIfPresent([WireLink].self, forKey: .links)) ?? []
        quotes = (try? container.decodeIfPresent([String].self, forKey: .quotes)) ?? []
        reminderMinutesBefore = try container.decodeIfPresent([Int].self, forKey: .reminderMinutesBefore)
        recurrence = try container.decodeIfPresent(WireRecurrence.self, forKey: .recurrence)
        ambiguities = try container.decodeIfPresent([String].self, forKey: .ambiguities) ?? []
    }
}

public struct WireRecurrence: Sendable, Hashable, Codable {
    public var frequency: String
    public var interval: Int?
    public var weekdays: [String]?
    public var count: Int?
    public var until: String?

    public init(frequency: String, interval: Int? = nil, weekdays: [String]? = nil, count: Int? = nil, until: String? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.count = count
        self.until = until
    }
}

public enum ExtractionSchema {
    // Built from small helpers: one big nested literal is slow (or impossible) to type-check.

    private static func field(_ type: String, _ description: String? = nil) -> JSONValue {
        var object: [String: JSONValue] = ["type": .string(type)]
        if let description { object["description"] = .string(description) }
        return .object(object)
    }

    private static func nullable(_ type: String, _ description: String? = nil) -> JSONValue {
        var object: [String: JSONValue] = ["type": .array([.string(type), .string("null")])]
        if let description { object["description"] = .string(description) }
        return .object(object)
    }

    private static func nullableArray(of items: JSONValue, _ description: String? = nil) -> JSONValue {
        var object: [String: JSONValue] = ["type": .array([.string("array"), .string("null")]), "items": items]
        if let description { object["description"] = .string(description) }
        return .object(object)
    }

    private static func enumeration(_ values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map { .string($0) })])
    }

    /// A strict object: every property required, nothing else allowed.
    private static func strictObject(_ properties: [(String, JSONValue)]) -> JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array(properties.map { .string($0.0) }),
            "properties": .object(Dictionary(properties, uniquingKeysWith: { first, _ in first })),
        ])
    }

    private static var recurrence: JSONValue {
        strictObject([
            ("frequency", enumeration(["daily", "weekly", "monthly", "yearly"])),
            ("interval", nullable("integer", "Every N periods; null means 1.")),
            ("weekdays", nullableArray(of: enumeration(["MO", "TU", "WE", "TH", "FR", "SA", "SU"]))),
            ("count", nullable("integer", "Number of occurrences, if stated.")),
            ("until", nullable("string", "Last date YYYY-MM-DD, if stated.")),
        ])
    }

    private static var event: JSONValue {
        strictObject([
            ("title", field("string", "Short, specific title in the language of the source.")),
            ("start", field("string", "Local start time YYYY-MM-DDTHH:MM, or YYYY-MM-DD for all-day events.")),
            ("end", nullable("string", "Local end time in the same format; null if not stated. For all-day events, the last day.")),
            ("all_day", field("boolean")),
            ("time_zone", nullable("string", "IANA time zone, only if the source states one explicitly.")),
            ("location", nullable("string", "Place or address.")),
            ("url", nullable("string", "The event's main link: online meeting, ticket, chat message or event page.")),
            ("notes", nullable("string", "Every detail from the typed text and the images not in the other fields, verbatim, in short paragraphs. Never drop facts from the typed text.")),
            ("links", .object([
                "type": .string("array"),
                "items": link,
                "description": .string("Every URL that belongs to this event, from the typed text and the images."),
            ])),
            ("quotes", .object([
                "type": .string("array"),
                "items": field("string"),
                "description": .string("Up to 3 key quotes from the chat, message or screenshot, verbatim; empty if none."),
            ])),
            ("reminder_minutes_before", nullableArray(of: field("integer"), "Only if reminders are explicitly requested; otherwise null.")),
            ("recurrence", .object(["anyOf": .array([recurrence, field("null")])])),
            ("ambiguities", .object([
                "type": .string("array"),
                "items": field("string"),
                "description": .string("Short notes, in the user's language, about anything guessed or unclear."),
            ])),
        ])
    }

    private static var link: JSONValue {
        strictObject([
            ("url", field("string", "The full URL as written in the source.")),
            ("label", nullable("string", "2–4 words saying what it is, in the user's language: \"Telegram message\", \"Zoom call\", \"Ticket\".")),
        ])
    }

    private static func stringList(_ description: String) -> JSONValue {
        .object(["type": .string("array"), "items": field("string"), "description": .string(description)])
    }

    private static var analysis: JSONValue {
        strictObject([
            ("typed_text_facts", stringList("Every fact, name, identifier, number and instruction in the text the user typed, one per item.")),
            ("image_facts", stringList("Every fact relevant to the events read from the images, one per item; empty without images.")),
            ("links", stringList("Every URL found in the typed text and in the images, exactly as written.")),
        ])
    }

    /// JSON Schema for `ExtractionResponse`, written for strict structured-output modes
    /// (every property required, `null` for absent values, no additional properties).
    public static var jsonSchema: JSONValue {
        strictObject([
            ("analysis", analysis),
            ("events", .object(["type": .string("array"), "items": event])),
        ])
    }
}
