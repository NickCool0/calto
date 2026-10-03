import Foundation

/// One request in the history: what was sent, what the model returned and what was saved.
/// Screenshots are kept only as small thumbnails, by file name in the history folder.
public struct HistoryEntry: Sendable, Hashable, Codable, Identifiable {
    public enum Status: String, Sendable, Hashable, Codable, CaseIterable {
        /// Events were added to the calendar.
        case created
        /// Recognized, but nothing was added (closed or went back without saving).
        case notAdded
        /// Added, then undone.
        case undone
        /// The model found no events.
        case noEvents
        /// The request failed (network, key, model error).
        case failed
    }

    public var id: UUID
    public var date: Date
    public var mode: AddMode
    /// Display name of the provider and the model, e.g. "Gemini" and "gemini-flash-lite-latest".
    public var provider: String
    public var model: String
    public var inputText: String?
    public var thumbnails: [String]
    /// The events as the model returned them (after date resolution and composing the notes).
    public var recognized: [EventDraft]
    /// What the model read from each source; kept for understanding odd results.
    public var analysis: WireAnalysis?
    /// The events as written to the calendar, after the user's edits.
    public var saved: [SavedEvent]
    public var status: Status
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        mode: AddMode,
        provider: String,
        model: String,
        inputText: String?,
        thumbnails: [String] = [],
        recognized: [EventDraft] = [],
        analysis: WireAnalysis? = nil,
        saved: [SavedEvent] = [],
        status: Status,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.provider = provider
        self.model = model
        self.inputText = inputText
        self.thumbnails = thumbnails
        self.recognized = recognized
        self.analysis = analysis
        self.saved = saved
        self.status = status
        self.errorMessage = errorMessage
    }

    /// The first saved (or recognized) title, for the list.
    public var displayTitle: String? {
        (saved.first?.draft.title ?? recognized.first?.title).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Recognized events the user unchecked or dropped before saving.
    public var excluded: [EventDraft] {
        guard status == .created || status == .undone else { return [] }
        let savedIDs = Set(saved.map(\.draft.id))
        return recognized.filter { !savedIDs.contains($0.id) }
    }

    /// Case- and diacritic-insensitive search over the request text and event titles and notes.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = [inputText ?? ""] + (saved.map(\.draft) + recognized).flatMap { [$0.title, $0.notes ?? "", $0.location ?? ""] }
        return haystack.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// An event calto wrote to a calendar.
public struct SavedEvent: Sendable, Hashable, Codable {
    public var draft: EventDraft
    public var calendarID: String
    public var calendarTitle: String
    /// EventKit identifier, for deleting or opening the event later.
    public var eventIdentifier: String?
    /// Set when the event was later deleted from history (or undone).
    public var removed: Bool

    public init(draft: EventDraft, calendarID: String, calendarTitle: String, eventIdentifier: String?, removed: Bool = false) {
        self.draft = draft
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.eventIdentifier = eventIdentifier
        self.removed = removed
    }
}

/// Which fields the user changed between the recognized event and the saved one.
public enum HistoryDiff {
    public enum Field: String, Sendable, Hashable, CaseIterable {
        case title, time, allDay, timeZone, location, link, notes, reminders, recurrence
    }

    public static func changedFields(from recognized: EventDraft, to saved: EventDraft) -> [Field] {
        var fields: [Field] = []
        if recognized.title.trimmingCharacters(in: .whitespacesAndNewlines) != saved.title.trimmingCharacters(in: .whitespacesAndNewlines) {
            fields.append(.title)
        }
        if recognized.start != saved.start || recognized.end != saved.end {
            fields.append(.time)
        }
        if recognized.isAllDay != saved.isAllDay {
            fields.append(.allDay)
        }
        if recognized.timeZone != saved.timeZone {
            fields.append(.timeZone)
        }
        if normalized(recognized.location) != normalized(saved.location) {
            fields.append(.location)
        }
        if recognized.url != saved.url {
            fields.append(.link)
        }
        if normalized(recognized.notes) != normalized(saved.notes) {
            fields.append(.notes)
        }
        if Set(recognized.alarms) != Set(saved.alarms) {
            fields.append(.reminders)
        }
        if recognized.recurrence != saved.recurrence {
            fields.append(.recurrence)
        }
        return fields
    }

    private static func normalized(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// How long history is kept.
public enum HistoryRetention: String, Sendable, Hashable, CaseIterable, Codable {
    case off
    case week
    case month
    case year
    case forever

    public var maxAge: TimeInterval? {
        let day: TimeInterval = 24 * 3600
        return switch self {
        case .off: 0
        case .week: 7 * day
        case .month: 30 * day
        case .year: 365 * day
        case .forever: nil
        }
    }
}

/// History on disk: `history.json` plus a `Thumbnails` folder, in the given directory.
public actor HistoryStore {
    public let directory: URL
    private var entries: [HistoryEntry]?

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appending(path: "history.json") }
    private var thumbnailsURL: URL { directory.appending(path: "Thumbnails", directoryHint: .isDirectory) }

    /// All entries, newest first.
    public func all() -> [HistoryEntry] {
        loaded().sorted { $0.date > $1.date }
    }

    public func entry(id: UUID) -> HistoryEntry? {
        loaded().first { $0.id == id }
    }

    /// Inserts or replaces the entry with the same id.
    public func save(_ entry: HistoryEntry) throws {
        var entries = loaded()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try write(entries)
    }

    public func delete(id: UUID) throws {
        var entries = loaded()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        removeThumbnails(of: entries[index])
        entries.remove(at: index)
        try write(entries)
    }

    public func deleteAll() throws {
        try? FileManager.default.removeItem(at: thumbnailsURL)
        try write([])
    }

    /// Drops entries older than the retention period (everything for `.off`).
    public func prune(_ retention: HistoryRetention, now: Date = .now) throws {
        guard let maxAge = retention.maxAge else { return }
        let entries = loaded()
        let kept = entries.filter { now.timeIntervalSince($0.date) < maxAge && maxAge > 0 }
        guard kept.count != entries.count else { return }
        for entry in entries where !kept.contains(where: { $0.id == entry.id }) {
            removeThumbnails(of: entry)
        }
        try write(kept)
    }

    /// Stores a thumbnail and returns its file name for `HistoryEntry.thumbnails`.
    public func saveThumbnail(_ data: Data, named name: String = "\(UUID().uuidString).jpg") throws -> String {
        try FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
        try data.write(to: thumbnailsURL.appending(path: name), options: .atomic)
        return name
    }

    public nonisolated func thumbnailURL(_ name: String) -> URL {
        directory.appending(path: "Thumbnails", directoryHint: .isDirectory).appending(path: name)
    }

    private func loaded() -> [HistoryEntry] {
        if let entries {
            return entries
        }
        let loaded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? []
        entries = loaded
        return loaded
    }

    private func write(_ entries: [HistoryEntry]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        self.entries = entries
    }

    private func removeThumbnails(of entry: HistoryEntry) {
        for name in entry.thumbnails {
            try? FileManager.default.removeItem(at: thumbnailURL(name))
        }
    }
}
