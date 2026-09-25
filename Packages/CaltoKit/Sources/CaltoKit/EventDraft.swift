import Foundation

/// An event recognized from user input, before it is written to a calendar.
///
/// Every field stays editable on the review screen; nothing is saved automatically.
public struct EventDraft: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var start: Date
    /// `nil` when the source did not mention an end; the default duration from settings applies.
    public var end: Date?
    public var isAllDay: Bool
    /// IANA identifier, set only when the source states a time zone explicitly.
    public var timeZoneIdentifier: String?
    public var location: String?
    public var meetingURL: URL?
    public var notes: String?
    /// Empty means "use the default reminders from settings".
    public var alarms: [EventAlarm]
    /// Human-readable notes about what the model could not determine unambiguously.
    public var ambiguities: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        start: Date,
        end: Date? = nil,
        isAllDay: Bool = false,
        timeZoneIdentifier: String? = nil,
        location: String? = nil,
        meetingURL: URL? = nil,
        notes: String? = nil,
        alarms: [EventAlarm] = [],
        ambiguities: [String] = []
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.location = location
        self.meetingURL = meetingURL
        self.notes = notes
        self.alarms = alarms
        self.ambiguities = ambiguities
    }
}

/// A reminder relative to the event start.
public struct EventAlarm: Sendable, Hashable, Codable {
    /// Minutes before the start; `0` fires at the start time.
    public var minutesBefore: Int

    public init(minutesBefore: Int) {
        self.minutesBefore = minutesBefore
    }
}
