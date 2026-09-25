/// Per-account restrictions that EventKit does not report but the server enforces.
public struct CalendarCapabilities: Sendable, Hashable {
    /// Maximum number of alarms per event, or `nil` when unlimited.
    public var maxAlarms: Int?

    public init(maxAlarms: Int?) {
        self.maxAlarms = maxAlarms
    }

    public init(accountKind: CalendarAccountKind) {
        switch accountKind {
        case .exchange:
            // Exchange stores a single reminder per item; extra EKAlarms are silently discarded on sync.
            self.init(maxAlarms: 1)
        default:
            self.init(maxAlarms: nil)
        }
    }

    /// Removes duplicate alarms and trims the list to `maxAlarms`, keeping the earliest-listed ones.
    public func limitingAlarms(_ alarms: [EventAlarm]) -> AlarmLimitResult {
        var seen = Set<EventAlarm>()
        let unique = alarms.filter { seen.insert($0).inserted }
        guard let maxAlarms, unique.count > maxAlarms else {
            return AlarmLimitResult(kept: unique, dropped: [])
        }
        return AlarmLimitResult(
            kept: Array(unique.prefix(maxAlarms)),
            dropped: Array(unique.dropFirst(maxAlarms))
        )
    }
}

public struct AlarmLimitResult: Sendable, Hashable {
    public var kept: [EventAlarm]
    /// Alarms that did not fit; the review screen shows a warning when this is not empty.
    public var dropped: [EventAlarm]

    public init(kept: [EventAlarm], dropped: [EventAlarm]) {
        self.kept = kept
        self.dropped = dropped
    }
}
