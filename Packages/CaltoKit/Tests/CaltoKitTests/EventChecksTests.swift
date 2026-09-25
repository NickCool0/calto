import Foundation
import Testing
@testable import CaltoKit

struct EventChecksTests {
    private let base = Date(timeIntervalSince1970: 1_790_416_800) // some day, 13:00 in Moscow

    private func draft(_ title: String, at offset: TimeInterval = 0, hours: Double = 1, allDay: Bool = false) -> EventDraft {
        let start = base.addingTimeInterval(offset)
        return EventDraft(title: title, start: start, end: start.addingTimeInterval(hours * 3600), isAllDay: allDay)
    }

    private func existing(_ title: String, at offset: TimeInterval = 0, hours: Double = 1, allDay: Bool = false, id: String? = nil) -> ExistingEvent {
        let start = base.addingTimeInterval(offset)
        return ExistingEvent(id: id ?? title, title: title, start: start, end: start.addingTimeInterval(hours * 3600), isAllDay: allDay, calendarTitle: "Work")
    }

    @Test("Same title at the same time is a duplicate, not a conflict")
    func duplicate() {
        let events = [existing("Встреча с Аней")]
        #expect(EventChecks.duplicates(of: draft("встреча с аней"), in: events).count == 1)
        #expect(EventChecks.conflicts(of: draft("встреча с аней"), in: events).isEmpty)
    }

    @Test("Similar titles within 30 minutes are duplicates", arguments: [
        ("Standup", "Daily standup"),
        ("Dentist appointment", "Dentist"),
        ("Кино: «Дюна»", "кино дюна"),
        ("Ёлка в школе", "елка в школе"),
        // The default prompt asks for an emoji at the start of the title.
        ("Покурить", "🚬 Покурить"),
        ("🛒 Магазин", "Магазин"),
    ])
    func similarTitles(existingTitle: String, draftTitle: String) {
        #expect(EventChecks.duplicates(of: draft(draftTitle, at: 20 * 60), in: [existing(existingTitle)]).count == 1)
    }

    @Test("Different titles or far-apart times are not duplicates")
    func notDuplicates() {
        #expect(EventChecks.duplicates(of: draft("Gym"), in: [existing("Dentist")]).isEmpty)
        #expect(EventChecks.duplicates(of: draft("Dentist", at: 2 * 3600), in: [existing("Dentist")]).isEmpty)
        #expect(EventChecks.duplicates(of: draft("Go"), in: [existing("Go to the gym and then dinner")]).isEmpty)
    }

    @Test("Overlapping timed events conflict; touching ones don't")
    func conflicts() {
        let events = [existing("Call", at: 30 * 60), existing("Lunch", at: 3600), existing("Earlier", at: -3600)]
        let found = EventChecks.conflicts(of: draft("Meeting"), in: events).map(\.title)
        #expect(found == ["Call"])
    }

    @Test("All-day events never conflict, in either direction")
    func allDay() {
        #expect(EventChecks.conflicts(of: draft("Meeting"), in: [existing("Holiday", hours: 24, allDay: true)]).isEmpty)
        #expect(EventChecks.conflicts(of: draft("Trip", hours: 0, allDay: true), in: [existing("Call")]).isEmpty)
    }

    @Test("All-day duplicates on the same day")
    func allDayDuplicate() {
        #expect(EventChecks.duplicates(of: draft("Mom's birthday", hours: 0, allDay: true), in: [existing("Mom’s birthday", hours: 0, allDay: true)]).count == 1)
    }
}
