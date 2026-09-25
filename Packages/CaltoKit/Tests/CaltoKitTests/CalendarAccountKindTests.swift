import Testing
import CaltoKit

struct CalendarAccountKindTests {
    @Test("Maps EventKit source type and title to an account kind", arguments: [
        (CalendarSourceType.local, "On My Mac", CalendarAccountKind.local),
        (.exchange, "Work", .exchange),
        (.calDAV, "iCloud", .iCloud),
        (.calDAV, " ICLOUD ", .iCloud),
        (.mobileMe, "MobileMe", .iCloud),
        (.calDAV, "Google", .google),
        (.calDAV, "someone@gmail.com", .google),
        (.calDAV, "someone@googlemail.com", .google),
        (.calDAV, "Fastmail", .otherCalDAV),
        (.subscribed, "Holidays", .subscribed),
        (.birthdays, "Birthdays", .birthdays),
        (.unknown, "Anything", .other),
    ])
    func mapsSource(sourceType: CalendarSourceType, title: String, expected: CalendarAccountKind) {
        #expect(CalendarAccountKind(sourceType: sourceType, sourceTitle: title) == expected)
    }

    @Test("Exchange is detected by source type, not by title")
    func exchangeIgnoresTitle() {
        #expect(CalendarAccountKind(sourceType: .exchange, sourceTitle: "iCloud") == .exchange)
    }
}
