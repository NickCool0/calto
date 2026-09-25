import AppKit
import CaltoKit
import EventKit
import Observation

enum CalendarAccessStatus {
    case notDetermined
    case fullAccess
    /// Granted "Add Events Only": calto can't read calendars, so conflicts, duplicates and undo won't work.
    case writeOnly
    case denied

    var localizedDescription: String {
        switch self {
        case .notDetermined: String(localized: "Not requested yet")
        case .fullAccess: String(localized: "Granted")
        case .writeOnly: String(localized: "Add-only (full access required)")
        case .denied: String(localized: "Denied")
        }
    }
}

struct CalendarAccount: Identifiable {
    let id: String
    let title: String
    let kind: CalendarAccountKind
    let capabilities: CalendarCapabilities
    let calendars: [CalendarSummary]
}

struct CalendarSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let color: NSColor
    let accountTitle: String
    let capabilities: CalendarCapabilities
}

/// Wraps `EKEventStore`: authorization and the list of calendars calto may write to.
@MainActor
@Observable
final class CalendarAccess {
    private(set) var status: CalendarAccessStatus
    private(set) var accounts: [CalendarAccount] = []
    private(set) var lastError: String?
    /// The calendar Calendar.app uses for new events.
    private(set) var systemDefaultCalendarID: String?

    @ObservationIgnored private var store = EKEventStore()
    @ObservationIgnored private var changeObserver: (any NSObjectProtocol)?

    init() {
        status = Self.currentStatus()
        reload()
        // Accounts and calendars can change at any time (added in Calendar.app, synced from the server).
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
    }

    /// Asks on first launch; later launches only read the stored decision.
    func requestAccessIfNeeded() async {
        guard status == .notDetermined else { return }
        // The system prompt is attached to the frontmost app, so a menu bar app must activate first.
        NSApp.activate()
        await requestAccess()
    }

    func requestAccess() async {
        do {
            _ = try await Self.requestFullAccess()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        status = Self.currentStatus()
        // A store created before authorization may keep returning no calendars; start fresh.
        store = EKEventStore()
        reload()
    }

    func reload() {
        guard status == .fullAccess else {
            accounts = []
            return
        }
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        let bySource = Dictionary(grouping: writable) { $0.source?.sourceIdentifier ?? "" }

        accounts = bySource.values
            .compactMap { calendars -> CalendarAccount? in
                guard let source = calendars.first?.source else { return nil }
                let kind = CalendarAccountKind(sourceType: CalendarSourceType(source.sourceType), sourceTitle: source.title)
                return CalendarAccount(
                    id: source.sourceIdentifier,
                    title: source.title,
                    kind: kind,
                    capabilities: CalendarCapabilities(accountKind: kind),
                    calendars: calendars
                        .map {
                            CalendarSummary(
                                id: $0.calendarIdentifier, title: $0.title, color: $0.color,
                                accountTitle: source.title, capabilities: CalendarCapabilities(accountKind: kind)
                            )
                        }
                        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        systemDefaultCalendarID = store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    var allCalendars: [CalendarSummary] {
        accounts.flatMap(\.calendars)
    }

    func calendar(withID id: String?) -> CalendarSummary? {
        guard let id else { return nil }
        return allCalendars.first { $0.id == id }
    }

    /// The preferred calendar if it still exists and is writable, otherwise Calendar.app's default.
    func resolvedCalendarID(preferred: String?) -> String? {
        calendar(withID: preferred)?.id ?? calendar(withID: systemDefaultCalendarID)?.id ?? allCalendars.first?.id
    }

    // MARK: Reading and writing events

    /// Events in all calendars overlapping the interval, for duplicate and conflict checks.
    func existingEvents(from start: Date, to end: Date) -> [ExistingEvent] {
        guard status == .fullAccess, start < end else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            ExistingEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar?.title ?? ""
            )
        }
    }

    /// Saves the events in one commit and returns their identifiers, for undo.
    func save(_ events: [(draft: EventDraft, calendarID: String)]) throws -> [String] {
        var saved: [EKEvent] = []
        do {
            for (draft, calendarID) in events {
                guard let calendar = store.calendar(withIdentifier: calendarID) else {
                    throw CalendarWriteError.calendarMissing
                }
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = draft.title
                event.isAllDay = draft.isAllDay
                event.startDate = draft.start
                event.endDate = draft.end
                if let zone = draft.timeZone, !draft.isAllDay {
                    event.timeZone = zone
                }
                event.location = draft.location
                event.url = draft.url
                event.notes = draft.notes

                let kind = self.calendar(withID: calendarID)?.capabilities ?? CalendarCapabilities(maxAlarms: nil)
                let alarms = kind.limitingAlarms(draft.alarms).kept
                event.alarms = alarms.map { EKAlarm(relativeOffset: -TimeInterval($0.minutesBefore * 60)) }
                if let recurrence = draft.recurrence {
                    event.recurrenceRules = [Self.rule(for: recurrence)]
                }
                try store.save(event, span: .thisEvent, commit: false)
                saved.append(event)
            }
            try store.commit()
        } catch {
            store.reset()
            throw error
        }
        return saved.compactMap(\.eventIdentifier)
    }

    /// Undo: deletes events calto just created (the whole series for recurring ones).
    func removeEvents(withIdentifiers identifiers: [String]) throws {
        for identifier in identifiers {
            if let event = store.event(withIdentifier: identifier) {
                try store.remove(event, span: .futureEvents, commit: false)
            }
        }
        try store.commit()
    }

    private static func rule(for recurrence: Recurrence) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency = switch recurrence.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let days = recurrence.weekdays.compactMap { EKWeekday(rawValue: $0.rawValue) }.map { EKRecurrenceDayOfWeek($0) }
        let end: EKRecurrenceEnd? = if let count = recurrence.count {
            EKRecurrenceEnd(occurrenceCount: count)
        } else if let until = recurrence.until {
            EKRecurrenceEnd(end: until)
        } else {
            nil
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: recurrence.interval,
            daysOfTheWeek: days.isEmpty ? nil : days,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private static func currentStatus() -> CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    /// Uses its own short-lived store so no non-Sendable state crosses actor boundaries.
    private nonisolated static func requestFullAccess() async throws -> Bool {
        try await EKEventStore().requestFullAccessToEvents()
    }
}

extension CalendarSourceType {
    init(_ sourceType: EKSourceType) {
        switch sourceType {
        case .local: self = .local
        case .exchange: self = .exchange
        case .calDAV: self = .calDAV
        case .mobileMe: self = .mobileMe
        case .subscribed: self = .subscribed
        case .birthdays: self = .birthdays
        @unknown default: self = .unknown
        }
    }
}

nonisolated enum CalendarWriteError: LocalizedError {
    case calendarMissing

    var errorDescription: String? {
        String(localized: "The chosen calendar is no longer available. Pick another one.")
    }
}
