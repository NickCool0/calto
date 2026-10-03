import Foundation

/// How recognized events reach the calendar.
public enum AddMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Every event is shown for review first.
    case review
    /// Clear results are added right away (with undo); anything doubtful still goes to review.
    case automatic
}

/// Why an automatic add stops at the review screen instead.
public enum ReviewReason: Sendable, Hashable {
    case noEvents
    case missingTitle(eventIndex: Int)
    case unreadableDate(title: String)
    /// Something adjusted while reading the answer (an end before the start, an unknown time zone…).
    case issue(title: String, issue: ResolutionIssue)
    case ambiguity(title: String, note: String)
    case duplicate(title: String, existingTitle: String)
    case conflict(title: String, existingTitle: String)
    case reminderLimit(title: String)
    case noCalendar
}

/// Decides whether recognized events are clear enough to add without review.
public enum AutoAddPolicy {
    /// - Parameters:
    ///   - existing: events already in the calendars around the recognized dates.
    ///   - capabilities: limits of the calendar the events would go to (`nil` when there is none).
    /// - Returns: every reason to review; empty means the events can be added automatically.
    public static func reasonsToReview(
        _ drafts: [EventDraft],
        existing: [ExistingEvent],
        capabilities: CalendarCapabilities?
    ) -> [ReviewReason] {
        guard !drafts.isEmpty else { return [.noEvents] }
        var reasons: [ReviewReason] = []
        if capabilities == nil {
            reasons.append(.noCalendar)
        }
        for (index, draft) in drafts.enumerated() {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                reasons.append(.missingTitle(eventIndex: index))
            }
            for issue in draft.issues {
                switch issue {
                case .invalidStart:
                    reasons.append(.unreadableDate(title: title))
                case .missingTitle:
                    break // reported above
                case .invalidEnd, .endBeforeStart, .unknownTimeZone, .unsupportedRecurrence:
                    reasons.append(.issue(title: title, issue: issue))
                }
            }
            for note in draft.ambiguities {
                reasons.append(.ambiguity(title: title, note: note))
            }
            for duplicate in EventChecks.duplicates(of: draft, in: existing) {
                reasons.append(.duplicate(title: title, existingTitle: duplicate.title))
            }
            for conflict in EventChecks.conflicts(of: draft, in: existing) {
                reasons.append(.conflict(title: title, existingTitle: conflict.title))
            }
            if let capabilities, !capabilities.limitingAlarms(draft.alarms).dropped.isEmpty {
                reasons.append(.reminderLimit(title: title))
            }
        }
        return reasons
    }
}
