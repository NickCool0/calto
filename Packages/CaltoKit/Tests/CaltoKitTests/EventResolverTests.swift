import Foundation
import Testing
@testable import CaltoKit

struct EventResolverTests {
    private let moscow = TimeZone(identifier: "Europe/Moscow")!
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    /// 2026-09-25 14:30 in Moscow.
    private var reference: Date { date("2026-09-25T14:30", moscow) }

    private func context(_ zone: TimeZone? = nil, duration: Int = 60, alarms: [EventAlarm] = [EventAlarm(minutesBefore: 15)]) -> ResolutionContext {
        ResolutionContext(timeZone: zone ?? moscow, referenceDate: reference, defaultDurationMinutes: duration, defaultAlarms: alarms)
    }

    private func date(_ string: String, _ zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return LocalDateTime(string)!.date(in: calendar, startOfDay: false)!
    }

    private func components(_ date: Date, _ zone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test("Local time is read in the user's time zone; missing end gets the default duration")
    func defaultDuration() {
        let draft = EventResolver.resolve(WireEvent(title: "Встреча", start: "2026-09-26T13:00"), context: context(duration: 45))
        #expect(components(draft.start, moscow) == DateComponents(year: 2026, month: 9, day: 26, hour: 13, minute: 0))
        #expect(draft.end.timeIntervalSince(draft.start) == 45 * 60)
        #expect(draft.timeZone == nil)
        #expect(draft.issues.isEmpty)
    }

    @Test("An explicit time zone wins and is kept on the event")
    func explicitTimeZone() {
        let draft = EventResolver.resolve(WireEvent(title: "Call", start: "2026-09-26T09:00", end: "2026-09-26T10:00", timeZone: "Europe/Berlin"), context: context())
        #expect(components(draft.start, berlin).hour == 9)
        #expect(components(draft.start, moscow).hour == 10)
        #expect(draft.timeZone == berlin)
    }

    @Test("A UTC offset in the string wins over any zone")
    func utcOffset() {
        let draft = EventResolver.resolve(WireEvent(title: "Launch", start: "2026-09-26T12:00Z"), context: context())
        #expect(components(draft.start, moscow).hour == 15)
    }

    @Test("Unknown time zones fall back to the user's and are reported")
    func unknownTimeZone() {
        let draft = EventResolver.resolve(WireEvent(title: "X", start: "2026-09-26T13:00", timeZone: "Mars/Olympus"), context: context())
        #expect(components(draft.start, moscow).hour == 13)
        #expect(draft.issues == [.unknownTimeZone("Mars/Olympus")])
        #expect(draft.timeZone == nil)
    }

    @Test("Single all-day event: start and end are the same day at midnight")
    func allDaySingle() {
        let draft = EventResolver.resolve(WireEvent(title: "Отпуск", start: "2026-10-01", allDay: true), context: context())
        #expect(draft.isAllDay)
        #expect(components(draft.start, moscow) == DateComponents(year: 2026, month: 10, day: 1, hour: 0, minute: 0))
        #expect(draft.end == draft.start)
    }

    @Test("Multi-day all-day event keeps its inclusive last day")
    func allDayRange() {
        let draft = EventResolver.resolve(WireEvent(title: "Conference", start: "2026-10-01", end: "2026-10-03", allDay: true), context: context())
        #expect(components(draft.end, moscow).day == 3)
    }

    @Test("A date without a time is all-day even if the flag is missing")
    func dateOnlyMeansAllDay() {
        let draft = EventResolver.resolve(WireEvent(title: "Birthday", start: "2026-10-05"), context: context())
        #expect(draft.isAllDay)
    }

    @Test("End before start falls back to the default duration and is reported")
    func endBeforeStart() {
        let draft = EventResolver.resolve(WireEvent(title: "X", start: "2026-09-26T15:00", end: "2026-09-26T14:00"), context: context())
        #expect(draft.end.timeIntervalSince(draft.start) == 3600)
        #expect(draft.issues == [.endBeforeStart])
    }

    @Test("Overnight events keep their next-day end")
    func overnight() {
        let draft = EventResolver.resolve(WireEvent(title: "Party", start: "2026-09-26T22:00", end: "2026-09-27T02:00"), context: context())
        #expect(draft.end.timeIntervalSince(draft.start) == 4 * 3600)
    }

    @Test("Unreadable start becomes a placeholder at the next full hour, with an issue", arguments: ["next Friday", "2026-02-30T10:00", "2026-13-01", ""])
    func invalidStart(value: String) {
        let draft = EventResolver.resolve(WireEvent(title: "X", start: value), context: context())
        #expect(components(draft.start, moscow) == DateComponents(year: 2026, month: 9, day: 25, hour: 15, minute: 0))
        #expect(draft.issues.contains(.invalidStart(value)))
    }

    @Test("A time in the spring-forward gap is moved forward, not rejected")
    func dstGap() {
        let draft = EventResolver.resolve(WireEvent(title: "Early", start: "2026-03-29T02:30"), context: context(berlin))
        #expect(draft.issues.isEmpty)
        let hour = components(draft.start, berlin).hour
        #expect(hour == 3)
    }

    @Test("Accepted formats", arguments: ["2026-09-26T13:00", "2026-09-26 13:00", "2026-09-26T13:00:00", "2026-9-26T13:00", "2026-09-26T13:00:00.000"])
    func formats(value: String) {
        let draft = EventResolver.resolve(WireEvent(title: "X", start: value), context: context())
        #expect(components(draft.start, moscow).hour == 13)
        #expect(draft.issues.isEmpty)
    }

    @Test("24:00 is the end of the day")
    func midnightEnd() {
        let draft = EventResolver.resolve(WireEvent(title: "X", start: "2026-09-26T22:00", end: "2026-09-26T24:00"), context: context())
        #expect(draft.end.timeIntervalSince(draft.start) == 2 * 3600)
    }

    @Test("No reminders mentioned: defaults from settings, marked as default")
    func defaultAlarms() {
        let draft = EventResolver.resolve(WireEvent(title: "X", start: "2026-09-26T13:00"), context: context())
        #expect(draft.alarms == [EventAlarm(minutesBefore: 15)])
        #expect(draft.alarmsAreDefault)
    }

    @Test("Explicit reminders replace defaults; an explicit empty list means none")
    func explicitAlarms() {
        let asked = EventResolver.resolve(WireEvent(title: "X", start: "2026-09-26T13:00", reminderMinutesBefore: [60, 10, 60, -5]), context: context())
        #expect(asked.alarms == [EventAlarm(minutesBefore: 10), EventAlarm(minutesBefore: 60)])
        #expect(!asked.alarmsAreDefault)
        let none = EventResolver.resolve(WireEvent(title: "X", start: "2026-09-26T13:00", reminderMinutesBefore: []), context: context())
        #expect(none.alarms.isEmpty)
        #expect(!none.alarmsAreDefault)
    }

    @Test("Recurrence: weekly on weekdays until an inclusive date")
    func recurrence() throws {
        let wire = WireEvent(
            title: "Standup", start: "2026-09-28T10:00",
            recurrence: WireRecurrence(frequency: "Weekly", interval: nil, weekdays: ["MO", "wednesday", "Fri", "xx"], until: "2026-12-31")
        )
        let rule = try #require(EventResolver.resolve(wire, context: context()).recurrence)
        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 1)
        #expect(rule.weekdays == [.monday, .wednesday, .friday])
        let until = try #require(rule.until)
        #expect(components(until, moscow) == DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 59))
    }

    @Test("Unknown recurrence is dropped and reported")
    func badRecurrence() {
        let draft = EventResolver.resolve(WireEvent(title: "X", start: "2026-09-28T10:00", recurrence: WireRecurrence(frequency: "fortnightly")), context: context())
        #expect(draft.recurrence == nil)
        #expect(draft.issues == [.unsupportedRecurrence("fortnightly")])
    }

    @Test("Links: full URLs, bare domains; plain words are not links")
    func links() {
        #expect(EventResolver.link(from: "https://zoom.us/j/123")?.absoluteString == "https://zoom.us/j/123")
        #expect(EventResolver.link(from: "meet.google.com/abc-defg-hij")?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(EventResolver.link(from: "Кафе на Арбате") == nil)
        #expect(EventResolver.link(from: "  ") == nil)
    }

    @Test("Blank strings become nil; blank title is reported")
    func blanks() {
        let draft = EventResolver.resolve(WireEvent(title: "  ", start: "2026-09-26T13:00", location: " ", notes: "", ambiguities: ["", "Год не указан"]), context: context())
        #expect(draft.location == nil)
        #expect(draft.notes == nil)
        #expect(draft.ambiguities == ["Год не указан"])
        #expect(draft.issues == [.missingTitle])
    }
}
