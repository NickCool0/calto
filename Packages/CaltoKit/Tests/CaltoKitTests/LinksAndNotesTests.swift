import Foundation
import Testing
@testable import CaltoKit

struct LinkDetectorTests {
    @Test("Finds web links in typed text, with or without a scheme, without duplicates")
    func links() {
        let text = """
        Сделай задачу на понедельник в 10
        Есть БД mesh-sch-pgsql-cl1, нужно сделать таску на удаление
        https://t.me/c/4323376323/670
        Ещё: t.me/c/4323376323/670 и zoom.us/j/123456?pwd=abc, почта a@b.ru
        """
        #expect(LinkDetector.links(in: text) == ["https://t.me/c/4323376323/670", "https://zoom.us/j/123456?pwd=abc"])
    }

    @Test("Comparison keys ignore scheme, www and a trailing slash")
    func keys() {
        #expect(LinkDetector.key(for: "https://www.Example.com/a/") == LinkDetector.key(for: "example.com/a"))
    }
}

struct NotesComposerTests {
    private let headings = NotesHeadings(links: "🔗 Ссылки:", context: "💬 Контекст:")

    @Test("Details, then every link with its label, then quotes")
    func layout() {
        let event = WireEvent(
            title: "🗑️ Удалить БД", start: "2026-10-05T10:00",
            url: "https://t.me/c/4323376323/670",
            notes: "Есть БД mesh-sch-pgsql-cl1, нужно сделать таску на удаление.",
            links: [WireLink(url: "https://t.me/c/4323376323/670", label: "Сообщение в Telegram")],
            quotes: ["«нужно сделать таску на удаление»"]
        )
        let notes = NotesComposer.compose([event], headings: headings)
        #expect(notes == ["""
        Есть БД mesh-sch-pgsql-cl1, нужно сделать таску на удаление.

        🔗 Ссылки:
        • Сообщение в Telegram — https://t.me/c/4323376323/670

        💬 Контекст:
        “нужно сделать таску на удаление”
        """])
    }

    @Test("A link the model dropped (as Flash Lite did) is restored from the typed text")
    func restoresDroppedLink() {
        let event = WireEvent(title: "Удалить БД", start: "2026-10-05T10:00", notes: "Удалить БД mesh-sch-pgsql-cl1")
        let typed = LinkDetector.links(in: "Есть БД mesh-sch-pgsql-cl1\nhttps://t.me/c/4323376323/670")
        let notes = NotesComposer.compose([event], extraLinks: typed, headings: headings)[0]
        #expect(notes?.contains("🔗 Ссылки:\n• https://t.me/c/4323376323/670") == true)
        #expect(notes?.hasPrefix("Удалить БД mesh-sch-pgsql-cl1") == true)
    }

    @Test("Links from url, links and the notes text are listed once each")
    func dedup() {
        let event = WireEvent(
            title: "Call", start: "2026-10-05T10:00",
            url: "zoom.us/j/1",
            notes: "Join https://zoom.us/j/1/ or https://meet.google.com/abc",
            links: [WireLink(url: "https://zoom.us/j/1", label: "Zoom")]
        )
        let links = NotesComposer.links(of: event)
        #expect(links.map(\.url) == ["https://zoom.us/j/1", "https://meet.google.com/abc"])
        #expect(links.first?.label == "Zoom")
    }

    @Test("Unassigned source links go to every event; assigned ones stay where they are")
    func severalEvents() {
        let first = WireEvent(title: "A", start: "2026-10-05T10:00", links: [WireLink(url: "https://a.example/1")])
        let second = WireEvent(title: "B", start: "2026-10-06T10:00")
        let notes = NotesComposer.compose([first, second], extraLinks: ["https://a.example/1", "https://b.example/2"], headings: headings)
        #expect(notes[0]?.contains("https://a.example/1") == true)
        #expect(notes[0]?.contains("https://b.example/2") == true)
        #expect(notes[1]?.contains("https://a.example/1") == false)
        #expect(notes[1]?.contains("https://b.example/2") == true)
    }

    @Test("Nothing to say gives no notes")
    func empty() {
        #expect(NotesComposer.compose([WireEvent(title: "X", start: "2026-10-05", notes: "  ", quotes: ["  "])]) == [nil])
    }

    @Test("The resolver composes the notes and picks the main link")
    func resolver() {
        let context = ResolutionContext(
            timeZone: TimeZone(identifier: "Europe/Moscow")!, referenceDate: .now,
            extraLinks: ["https://t.me/c/1/2"], headings: headings
        )
        let draft = EventResolver.resolve(WireEvent(title: "X", start: "2026-10-05T10:00", notes: "Details"), context: context)
        #expect(draft.notes == "Details\n\n🔗 Ссылки:\n• https://t.me/c/1/2")
        #expect(draft.url == nil)
        let linked = EventResolver.resolve(WireEvent(title: "X", start: "2026-10-05T10:00", links: [WireLink(url: "https://zoom.us/j/9")]), context: context)
        #expect(linked.url?.absoluteString == "https://zoom.us/j/9")
    }

    @Test("Answers with analysis, links and quotes decode; older answers without them still do")
    func decoding() throws {
        let json = #"{"analysis":{"typed_text_facts":["БД mesh-sch-pgsql-cl1"],"image_facts":[],"links":["https://t.me/c/1/2"]},"events":[{"title":"X","start":"2026-10-05T10:00","end":null,"all_day":false,"time_zone":null,"location":null,"url":null,"notes":null,"links":[{"url":"https://t.me/c/1/2","label":null}],"quotes":[],"reminder_minutes_before":null,"recurrence":null,"ambiguities":[]}]}"#
        let response = try ExtractionResponseParser.response(fromOutput: json)
        #expect(response.analysis?.typedTextFacts == ["БД mesh-sch-pgsql-cl1"])
        #expect(response.events.first?.links == [WireLink(url: "https://t.me/c/1/2")])
        let old = try ExtractionResponseParser.response(fromOutput: #"{"events":[{"title":"X","start":"2026-10-05"}]}"#)
        #expect(old.analysis == nil)
        #expect(old.events.first?.links == [])
    }
}

struct AutoAddPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_790_416_800)

    private func draft(_ title: String, ambiguities: [String] = [], issues: [ResolutionIssue] = [], alarms: [EventAlarm] = []) -> EventDraft {
        EventDraft(title: title, start: start, end: start.addingTimeInterval(3600), alarms: alarms, ambiguities: ambiguities, issues: issues)
    }

    private let calendar = CalendarCapabilities(maxAlarms: nil)

    @Test("Clear events are added automatically")
    func clear() {
        #expect(AutoAddPolicy.reasonsToReview([draft("Dentist")], existing: [], capabilities: calendar).isEmpty)
    }

    @Test("Any doubt sends the request to review")
    func doubts() {
        let existing = [ExistingEvent(id: "1", title: "Dentist", start: start, end: start.addingTimeInterval(3600), isAllDay: false, calendarTitle: "Home")]
        #expect(AutoAddPolicy.reasonsToReview([], existing: [], capabilities: calendar) == [.noEvents])
        #expect(AutoAddPolicy.reasonsToReview([draft(" ")], existing: [], capabilities: calendar) == [.missingTitle(eventIndex: 0)])
        #expect(AutoAddPolicy.reasonsToReview([draft("X", ambiguities: ["Год не указан"])], existing: [], capabilities: calendar) == [.ambiguity(title: "X", note: "Год не указан")])
        #expect(AutoAddPolicy.reasonsToReview([draft("X", issues: [.invalidStart("??")])], existing: [], capabilities: calendar) == [.unreadableDate(title: "X")])
        #expect(AutoAddPolicy.reasonsToReview([draft("Dentist")], existing: existing, capabilities: calendar) == [.duplicate(title: "Dentist", existingTitle: "Dentist")])
        #expect(AutoAddPolicy.reasonsToReview([draft("Gym")], existing: existing, capabilities: calendar) == [.conflict(title: "Gym", existingTitle: "Dentist")])
        #expect(AutoAddPolicy.reasonsToReview([draft("X")], existing: [], capabilities: nil) == [.noCalendar])
        let twoAlarms = draft("X", alarms: [EventAlarm(minutesBefore: 15), EventAlarm(minutesBefore: 30)])
        #expect(AutoAddPolicy.reasonsToReview([twoAlarms], existing: [], capabilities: CalendarCapabilities(maxAlarms: 1)) == [.reminderLimit(title: "X")])
    }
}

struct HistoryTests {
    private let start = Date(timeIntervalSince1970: 1_790_416_800)

    private func draft(_ title: String = "Dentist") -> EventDraft {
        EventDraft(title: title, start: start, end: start.addingTimeInterval(3600), notes: "Bring card", alarms: [EventAlarm(minutesBefore: 15)])
    }

    @Test("Changed fields between the recognized and the saved event")
    func diff() {
        let recognized = draft()
        var saved = recognized
        #expect(HistoryDiff.changedFields(from: recognized, to: saved).isEmpty)
        saved.title = "🦷 Dentist"
        saved.start = start.addingTimeInterval(3600)
        saved.end = start.addingTimeInterval(7200)
        saved.alarms = [EventAlarm(minutesBefore: 60)]
        saved.notes = " Bring card \n"
        #expect(HistoryDiff.changedFields(from: recognized, to: saved) == [.title, .time, .reminders])
    }

    @Test("Excluded events and search")
    func entry() {
        let kept = draft("Dentist")
        let dropped = draft("Gym")
        let entry = HistoryEntry(
            mode: .review, provider: "Gemini", model: "flash", inputText: "Стоматолог в среду",
            recognized: [kept, dropped],
            saved: [SavedEvent(draft: kept, calendarID: "c", calendarTitle: "Home", eventIdentifier: "e")],
            status: .created
        )
        #expect(entry.excluded == [dropped])
        #expect(entry.displayTitle == "Dentist")
        #expect(entry.matches("стоматолог"))
        #expect(entry.matches("BRING"))
        #expect(!entry.matches("Paris"))
    }

    @Test("The store saves, replaces, prunes and deletes entries with their thumbnails")
    func store() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "calto-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)

        let thumbnail = try await store.saveThumbnail(Data([1, 2, 3]))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var recent = HistoryEntry(date: now.addingTimeInterval(-3600), mode: .automatic, provider: "P", model: "M", inputText: "a", thumbnails: [thumbnail], status: .created)
        let old = HistoryEntry(date: now.addingTimeInterval(-40 * 24 * 3600), mode: .review, provider: "P", model: "M", inputText: "b", status: .failed)
        try await store.save(recent)
        try await store.save(old)
        recent.status = .undone
        try await store.save(recent)

        let reloaded = HistoryStore(directory: directory)
        #expect(await reloaded.all().map(\.id) == [recent.id, old.id])
        #expect(await reloaded.entry(id: recent.id)?.status == .undone)

        try await reloaded.prune(.month, now: now)
        #expect(await reloaded.all().map(\.id) == [recent.id])

        try await reloaded.delete(id: recent.id)
        #expect(await reloaded.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: reloaded.thumbnailURL(thumbnail).path()))
    }

    @Test("Retention periods")
    func retention() {
        #expect(HistoryRetention.off.maxAge == 0)
        #expect(HistoryRetention.forever.maxAge == nil)
        #expect(HistoryRetention.month.maxAge == TimeInterval(30 * 24 * 3600))
    }
}
