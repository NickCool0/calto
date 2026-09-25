import AppKit
import CaltoKit
import Observation

/// One recognized event on the review screen.
struct ReviewItem: Identifiable {
    var draft: EventDraft
    var isIncluded = true
    var calendarID: String?

    var id: UUID { draft.id }
}

/// Everything the popover shows: input → recognizing → review → saved.
@MainActor
@Observable
final class PopoverModel {
    enum Phase {
        case input
        case recognizing
        case review
        case saved(count: Int, identifiers: [String])
    }

    let input = InputModel()
    private(set) var phase = Phase.input
    var items: [ReviewItem] = []
    /// Events already in the calendars around the recognized dates, for duplicate/conflict warnings.
    private(set) var existing: [ExistingEvent] = []
    private(set) var reviewError: String?

    let settings: AppSettings
    let calendarAccess: CalendarAccess
    private let recognition = RecognitionService()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(settings: AppSettings, calendarAccess: CalendarAccess) {
        self.settings = settings
        self.calendarAccess = calendarAccess
    }

    var isRecognizing: Bool {
        if case .recognizing = phase { return true }
        return false
    }

    var includedCount: Int {
        items.filter(\.isIncluded).count
    }

    var canSave: Bool {
        includedCount > 0 && items.allSatisfy { !$0.isIncluded || (!$0.draft.title.trimmed.isEmpty && $0.calendarID != nil) }
    }

    // MARK: Recognition

    func recognize() {
        guard !isRecognizing else { return }
        guard settings.isProviderReady else {
            input.showError(String(localized: "Set up a model in Settings first."))
            return
        }
        guard let request = input.makeRequest(settings: settings) else { return }

        input.clearNotice()
        phase = .recognizing
        task = Task {
            do {
                let drafts = try await recognition.recognize(request, settings: settings)
                try Task.checkCancellation()
                showReview(drafts)
            } catch is CancellationError {
                phase = .input
            } catch {
                phase = .input
                input.showError(error.localizedDescription)
            }
        }
    }

    func cancelRecognition() {
        task?.cancel()
        task = nil
        phase = .input
    }

    private func showReview(_ drafts: [EventDraft]) {
        guard !drafts.isEmpty else {
            phase = .input
            input.showInfo(String(localized: "No events found. Try adding details or an instruction."))
            return
        }
        let calendarID = calendarAccess.resolvedCalendarID(preferred: settings.defaultCalendarID)
        items = drafts.map { ReviewItem(draft: $0, calendarID: calendarID) }
        loadExistingEvents()
        reviewError = nil
        phase = .review
    }

    private func loadExistingEvents() {
        guard let first = items.map(\.draft.start).min(), let last = items.map(\.draft.end).max() else { return }
        let day: TimeInterval = 24 * 3600
        existing = calendarAccess.existingEvents(from: first.addingTimeInterval(-day), to: last.addingTimeInterval(day))
    }

    func backToInput() {
        phase = .input
        items = []
        input.requestFocus()
    }

    // MARK: Review warnings

    func duplicates(for item: ReviewItem) -> [ExistingEvent] {
        EventChecks.duplicates(of: item.draft, in: existing)
    }

    func conflicts(for item: ReviewItem) -> [ExistingEvent] {
        EventChecks.conflicts(of: item.draft, in: existing)
    }

    func alarmLimit(for item: ReviewItem) -> AlarmLimitResult? {
        guard let calendar = calendarAccess.calendar(withID: item.calendarID) else { return nil }
        let result = calendar.capabilities.limitingAlarms(item.draft.alarms)
        return result.dropped.isEmpty ? nil : result
    }

    // MARK: Saving

    func save() {
        let toSave = items
            .filter(\.isIncluded)
            .compactMap { item -> (draft: EventDraft, calendarID: String)? in
                guard let calendarID = item.calendarID else { return nil }
                var draft = item.draft
                draft.title = draft.title.trimmed
                return (draft, calendarID)
            }
        do {
            let identifiers = try calendarAccess.save(toSave)
            phase = .saved(count: identifiers.count, identifiers: identifiers)
            items = []
            input.clear()
        } catch {
            reviewError = error.localizedDescription
        }
    }

    func undo() {
        guard case .saved(_, let identifiers) = phase else { return }
        do {
            try calendarAccess.removeEvents(withIdentifiers: identifiers)
            phase = .input
            input.showInfo(String(localized: "The events were removed from your calendar."))
        } catch {
            input.showError(String(localized: "Couldn’t remove the events: \(error.localizedDescription)"))
            phase = .input
        }
    }

    func startOver() {
        phase = .input
        input.requestFocus()
    }

    func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
