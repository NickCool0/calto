import Foundation

/// Preferences and context used to turn the model's answer into concrete events.
public struct ResolutionContext: Sendable, Hashable {
    /// The user's time zone; times without an explicit zone are read in it.
    public var timeZone: TimeZone
    /// When the request was made; placeholder time for events whose date could not be read.
    public var referenceDate: Date
    /// Used when the source states no end.
    public var defaultDurationMinutes: Int
    /// Used when the source mentions no reminders.
    public var defaultAlarms: [EventAlarm]

    public init(timeZone: TimeZone, referenceDate: Date, defaultDurationMinutes: Int = 60, defaultAlarms: [EventAlarm] = []) {
        self.timeZone = timeZone
        self.referenceDate = referenceDate
        self.defaultDurationMinutes = defaultDurationMinutes
        self.defaultAlarms = defaultAlarms
    }
}

/// Turns `WireEvent`s (local wall-clock strings) into `EventDraft`s (absolute dates).
/// Relative dates are resolved by the model from the context in the prompt; this does the rest
/// deterministically, so date handling is testable without a model.
public enum EventResolver {
    public static func resolve(_ events: [WireEvent], context: ResolutionContext) -> [EventDraft] {
        events.map { resolve($0, context: context) }
    }

    public static func resolve(_ wire: WireEvent, context: ResolutionContext) -> EventDraft {
        var issues: [ResolutionIssue] = []

        var zone = context.timeZone
        var explicitZone: TimeZone?
        if let identifier = wire.timeZone?.trimmingCharacters(in: .whitespaces), !identifier.isEmpty {
            if let stated = TimeZone(identifier: identifier) ?? TimeZone(abbreviation: identifier) {
                zone = stated
                explicitZone = stated
            } else {
                issues.append(.unknownTimeZone(identifier))
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let startValue = LocalDateTime(wire.start)
        let endValue = wire.end.flatMap { $0.isEmpty ? nil : LocalDateTime($0) }
        // A date without a time means all day, whatever the flag says.
        let isAllDay = wire.allDay || (startValue != nil && startValue?.hasTime == false)

        var start: Date
        if let startValue, let date = startValue.date(in: calendar, startOfDay: isAllDay) {
            start = date
        } else {
            issues.append(.invalidStart(wire.start))
            start = placeholderStart(after: context.referenceDate, calendar: calendar)
        }

        var end: Date
        if isAllDay {
            start = calendar.startOfDay(for: start)
            if let endValue, let date = endValue.date(in: calendar, startOfDay: true) {
                end = calendar.startOfDay(for: date)
            } else {
                if let raw = wire.end, !raw.isEmpty { issues.append(.invalidEnd(raw)) }
                end = start
            }
            if end < start {
                issues.append(.endBeforeStart)
                end = start
            }
        } else {
            let fallback = start.addingTimeInterval(TimeInterval(max(context.defaultDurationMinutes, 1) * 60))
            if let endValue, let date = endValue.date(in: calendar, startOfDay: false) {
                if date > start {
                    end = date
                } else {
                    issues.append(.endBeforeStart)
                    end = fallback
                }
            } else {
                if let raw = wire.end, !raw.isEmpty { issues.append(.invalidEnd(raw)) }
                end = fallback
            }
        }

        let title = wire.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            issues.append(.missingTitle)
        }

        let alarms: [EventAlarm]
        let alarmsAreDefault: Bool
        if let minutes = wire.reminderMinutesBefore {
            alarms = Array(Set(minutes.filter { $0 >= 0 }.map(EventAlarm.init(minutesBefore:)))).sorted()
            alarmsAreDefault = false
        } else {
            alarms = context.defaultAlarms
            alarmsAreDefault = true
        }

        var recurrence: Recurrence?
        if let wireRecurrence = wire.recurrence {
            if let resolved = resolve(wireRecurrence, calendar: calendar) {
                recurrence = resolved
            } else {
                issues.append(.unsupportedRecurrence(wireRecurrence.frequency))
            }
        }

        return EventDraft(
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            timeZone: isAllDay ? nil : explicitZone,
            location: nonEmpty(wire.location),
            url: link(from: wire.url),
            notes: nonEmpty(wire.notes),
            alarms: alarms,
            alarmsAreDefault: alarmsAreDefault,
            recurrence: recurrence,
            ambiguities: wire.ambiguities.compactMap(nonEmpty),
            issues: issues
        )
    }

    static func resolve(_ wire: WireRecurrence, calendar: Calendar) -> Recurrence? {
        guard let frequency = Recurrence.Frequency(rawValue: wire.frequency.lowercased()) else { return nil }
        let until = wire.until
            .flatMap { LocalDateTime($0) }
            .flatMap { $0.date(in: calendar, startOfDay: true) }
            // The whole last day is included.
            .flatMap { calendar.date(byAdding: DateComponents(day: 1, second: -1), to: $0) }
        return Recurrence(
            frequency: frequency,
            interval: max(wire.interval ?? 1, 1),
            weekdays: (wire.weekdays ?? []).compactMap(Weekday.init(code:)),
            count: wire.count.flatMap { $0 > 0 ? $0 : nil },
            until: until
        )
    }

    /// Next full hour after the reference date.
    static func placeholderStart(after date: Date, calendar: Calendar) -> Date {
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return hour.addingTimeInterval(3600)
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Accepts full URLs and bare domains ("zoom.us/j/123").
    public static func link(from text: String?) -> URL? {
        guard let text = nonEmpty(text), !text.contains(" ") else { return nil }
        if let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty, url.host() != nil || scheme != "http" && scheme != "https" {
            return url
        }
        if text.contains("."), let url = URL(string: "https://\(text)"), url.host() != nil {
            return url
        }
        return nil
    }
}

/// A local date or date-time as the model writes it: `2026-09-26`, `2026-09-26T13:00`,
/// `2026-09-26 13:00:00`, optionally with a UTC offset (`Z`, `+03:00`) that then wins over any zone.
struct LocalDateTime: Hashable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int?
    var minute: Int?
    var second: Int?
    /// Seconds east of UTC, when the string carries an offset.
    var utcOffset: Int?

    var hasTime: Bool { hour != nil }

    init?(_ string: String) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?)?\s*(Z|[+-]\d{2}:?\d{2})?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }

        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }

        guard let year = group(1).flatMap(Int.init), let month = group(2).flatMap(Int.init), let day = group(3).flatMap(Int.init),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
        hour = group(4).flatMap(Int.init)
        minute = group(5).flatMap(Int.init)
        second = group(6).flatMap(Int.init)
        if let hour, !(0...24).contains(hour) { return nil }
        if let minute, !(0...59).contains(minute) { return nil }

        if let offset = group(7) {
            if offset == "Z" {
                utcOffset = 0
            } else {
                let digits = offset.dropFirst().replacingOccurrences(of: ":", with: "")
                let hours = Int(digits.prefix(2)) ?? 0
                let minutes = Int(digits.suffix(2)) ?? 0
                utcOffset = (offset.hasPrefix("-") ? -1 : 1) * (hours * 3600 + minutes * 60)
            }
        }
    }

    /// The instant in `calendar`'s time zone (or the string's own offset). Rejects impossible dates
    /// like February 30 instead of rolling them over.
    func date(in calendar: Calendar, startOfDay: Bool) -> Date? {
        var calendar = calendar
        if let utcOffset, let zone = TimeZone(secondsFromGMT: utcOffset) {
            calendar.timeZone = zone
        }
        var components = DateComponents(year: year, month: month, day: day)
        // Validate the day alone: a wall-clock time inside a DST gap is still a real (adjusted) instant.
        guard components.isValidDate(in: calendar) else { return nil }
        if !startOfDay, let hour {
            // "24:00" means the end of that day.
            components.hour = hour == 24 ? 0 : hour
            components.minute = minute ?? 0
            components.second = second ?? 0
        }
        guard var date = calendar.date(from: components) else { return nil }
        if !startOfDay, hour == 24 {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }
}
