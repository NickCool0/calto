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
}

struct CalendarAccount: Identifiable {
    let id: String
    let title: String
    let kind: CalendarAccountKind
    let capabilities: CalendarCapabilities
    let calendars: [CalendarSummary]
}

struct CalendarSummary: Identifiable {
    let id: String
    let title: String
    let color: NSColor
}

/// Wraps `EKEventStore`: authorization and the list of calendars calto may write to.
@MainActor
@Observable
final class CalendarAccess {
    private(set) var status: CalendarAccessStatus
    private(set) var accounts: [CalendarAccount] = []
    private(set) var lastError: String?

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
                        .map { CalendarSummary(id: $0.calendarIdentifier, title: $0.title, color: $0.color) }
                        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
