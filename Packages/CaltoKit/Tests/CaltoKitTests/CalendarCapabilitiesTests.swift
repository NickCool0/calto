import Testing
import CaltoKit

struct CalendarCapabilitiesTests {
    private let fifteen = EventAlarm(minutesBefore: 15)
    private let hour = EventAlarm(minutesBefore: 60)
    private let day = EventAlarm(minutesBefore: 1440)

    @Test("Only Exchange accounts limit the number of alarms", arguments: CalendarAccountKind.allCases)
    func alarmLimitPerKind(kind: CalendarAccountKind) {
        let expected: Int? = kind == .exchange ? 1 : nil
        #expect(CalendarCapabilities(accountKind: kind).maxAlarms == expected)
    }

    @Test("Exchange keeps the first alarm and reports the rest as dropped")
    func exchangeTrimsAlarms() {
        let result = CalendarCapabilities(accountKind: .exchange).limitingAlarms([hour, fifteen, day])
        #expect(result.kept == [hour])
        #expect(result.dropped == [fifteen, day])
    }

    @Test("Unlimited accounts keep every alarm")
    func unlimitedKeepsAll() {
        let result = CalendarCapabilities(accountKind: .iCloud).limitingAlarms([hour, fifteen, day])
        #expect(result.kept == [hour, fifteen, day])
        #expect(result.dropped.isEmpty)
    }

    @Test("Duplicates are removed before the limit is applied")
    func duplicatesDoNotCountTowardsLimit() {
        let result = CalendarCapabilities(maxAlarms: 2).limitingAlarms([hour, hour, fifteen])
        #expect(result.kept == [hour, fifteen])
        #expect(result.dropped.isEmpty)
    }

    @Test("No alarms stays no alarms")
    func emptyInput() {
        let result = CalendarCapabilities(accountKind: .exchange).limitingAlarms([])
        #expect(result.kept.isEmpty)
        #expect(result.dropped.isEmpty)
    }
}
