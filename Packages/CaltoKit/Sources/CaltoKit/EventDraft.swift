import Foundation

/// An event recognized from user input, before it is written to a calendar.
///
/// Every field stays editable on the review screen; nothing is saved automatically.
/// For all-day events `start` is the first day and `end` the last day (both at midnight, inclusive).
public struct EventDraft: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Set only when the source stated a time zone explicitly; otherwise the user's time zone applies.
    public var timeZone: TimeZone?
    public var location: String?
    public var url: URL?
    public var notes: String?
    public var alarms: [EventAlarm]
    /// `true` when the source mentioned no reminders and the defaults from settings were applied.
    public var alarmsAreDefault: Bool
    public var recurrence: Recurrence?
    /// What the model could not determine unambiguously, in the user's language.
    public var ambiguities: [String]
    /// Problems found while turning the model's answer into dates.
    public var issues: [ResolutionIssue]

    public init(
        id: UUID = UUID(),
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        timeZone: TimeZone? = nil,
        location: String? = nil,
        url: URL? = nil,
        notes: String? = nil,
        alarms: [EventAlarm] = [],
        alarmsAreDefault: Bool = false,
        recurrence: Recurrence? = nil,
        ambiguities: [String] = [],
        issues: [ResolutionIssue] = []
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZone = timeZone
        self.location = location
        self.url = url
        self.notes = notes
        self.alarms = alarms
        self.alarmsAreDefault = alarmsAreDefault
        self.recurrence = recurrence
        self.ambiguities = ambiguities
        self.issues = issues
    }
}

/// A reminder relative to the event start.
public struct EventAlarm: Sendable, Hashable, Codable, Comparable {
    /// Minutes before the start; `0` fires at the start time.
    public var minutesBefore: Int

    public init(minutesBefore: Int) {
        self.minutesBefore = minutesBefore
    }

    public static func < (lhs: EventAlarm, rhs: EventAlarm) -> Bool {
        lhs.minutesBefore < rhs.minutesBefore
    }
}

public struct Recurrence: Sendable, Hashable, Codable {
    public enum Frequency: String, Sendable, Hashable, Codable, CaseIterable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    public var interval: Int
    public var weekdays: [Weekday]
    public var count: Int?
    public var until: Date?

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Weekday] = [], count: Int? = nil, until: Date? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.count = count
        self.until = until
    }
}

/// Days of the week, numbered like `Calendar` (Sunday = 1).
public enum Weekday: Int, Sendable, Hashable, Codable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// Accepts "MO", "Mon", "monday" (any case).
    public init?(code: String) {
        let prefix = code.trimmingCharacters(in: .whitespaces).lowercased().prefix(2)
        switch prefix {
        case "su": self = .sunday
        case "mo": self = .monday
        case "tu": self = .tuesday
        case "we": self = .wednesday
        case "th": self = .thursday
        case "fr": self = .friday
        case "sa": self = .saturday
        default: return nil
        }
    }
}

public enum ResolutionIssue: Sendable, Hashable, Codable {
    /// The start could not be read; the event was placed at a placeholder time.
    case invalidStart(String)
    case invalidEnd(String)
    /// The end was before the start; the default duration was used instead.
    case endBeforeStart
    case unknownTimeZone(String)
    case unsupportedRecurrence(String)
    case missingTitle
}
