import Foundation

/// The structured answer every provider must return, and its JSON Schema.
///
/// Dates are local wall-clock strings so the model never does time-zone arithmetic;
/// `EventResolver` turns them into `Date`s using the user's (or the stated) time zone.
public struct ExtractionResponse: Sendable, Hashable, Codable {
    public var events: [WireEvent]

    public init(events: [WireEvent]) {
        self.events = events
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
    /// `nil` means reminders were not mentioned.
    public var reminderMinutesBefore: [Int]?
    public var recurrence: WireRecurrence?
    public var ambiguities: [String]

    enum CodingKeys: String, CodingKey {
        case title, start, end, location, url, notes, recurrence, ambiguities
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
            ("url", nullable("string", "Online meeting link or event page.")),
            ("notes", nullable("string", "Other useful details from the source.")),
            ("reminder_minutes_before", nullableArray(of: field("integer"), "Only if reminders are explicitly requested; otherwise null.")),
            ("recurrence", .object(["anyOf": .array([recurrence, field("null")])])),
            ("ambiguities", .object([
                "type": .string("array"),
                "items": field("string"),
                "description": .string("Short notes, in the user's language, about anything guessed or unclear."),
            ])),
        ])
    }

    /// JSON Schema for `ExtractionResponse`, written for strict structured-output modes
    /// (every property required, `null` for absent values, no additional properties).
    public static var jsonSchema: JSONValue {
        strictObject([("events", .object(["type": .string("array"), "items": event]))])
    }
}
