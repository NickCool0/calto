import Foundation

/// An event already in the user's calendars, reduced to what the checks need.
public struct ExistingEvent: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarTitle: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, calendarTitle: String) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
    }
}

/// Warnings for the review screen: likely duplicates and time conflicts with existing events.
public enum EventChecks {
    /// Start times this close count as "the same event" when titles match.
    public static let duplicateWindow: TimeInterval = 30 * 60

    public static func duplicates(of draft: EventDraft, in existing: [ExistingEvent]) -> [ExistingEvent] {
        existing.filter { event in
            // Both all-day events start at local midnight, so "same day" means starts under 12 h apart.
            let sameDay = draft.isAllDay && event.isAllDay
                && abs(event.start.timeIntervalSince(draft.start)) < 12 * 3600
            let closeStart = abs(event.start.timeIntervalSince(draft.start)) <= duplicateWindow
            return (sameDay || closeStart) && titlesMatch(event.title, draft.title)
        }
    }

    /// Timed events that overlap the draft. All-day events don't block time, so they never conflict.
    public static func conflicts(of draft: EventDraft, in existing: [ExistingEvent]) -> [ExistingEvent] {
        guard !draft.isAllDay else { return [] }
        let duplicateIDs = Set(duplicates(of: draft, in: existing).map(\.id))
        return existing.filter { event in
            !event.isAllDay && !duplicateIDs.contains(event.id)
                && event.start < draft.end && draft.start < event.end
        }
    }

    /// Case-, accent- and punctuation-insensitive; one title containing the other also matches
    /// ("Standup" vs "Daily standup"), and so do titles sharing most of their words.
    static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalize(lhs)
        let b = normalize(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        if shorter.count >= 4 && longer.contains(shorter) { return true }
        let wordsA = Set(a.split(separator: " "))
        let wordsB = Set(b.split(separator: " "))
        let shared = wordsA.intersection(wordsB).count
        return Double(shared) / Double(wordsA.union(wordsB).count) >= 0.6
    }

    static func normalize(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ё", with: "е")
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
