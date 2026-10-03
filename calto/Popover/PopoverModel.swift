import AppKit
import CaltoKit
import Observation

/// One event on the review screen: a recognized one, or an already created one being edited.
struct ReviewItem: Identifiable {
    var draft: EventDraft
    var isIncluded = true
    var calendarID: String?
    /// Set when editing an event calto already created; saving updates it instead of adding a copy.
    var eventIdentifier: String?

    var id: UUID { draft.id }
}

/// Everything the popover shows: input (recognition runs in place) → review → saved.
@MainActor
@Observable
final class PopoverModel {
    enum Phase {
        case input
        case review
        case saved([SavedEvent])
    }

    let input = InputModel()
    private(set) var phase = Phase.input
    /// Non-nil only while a request is really running.
    private(set) var stage: RecognitionStage? {
        didSet {
            if (stage == .unlockingKey) != (oldValue == .unlockingKey) {
                onKeychainAccess?(stage == .unlockingKey)
            }
            if (stage == nil) != (oldValue == nil) {
                onActivityChanged?(stage != nil)
            }
        }
    }
    var items: [ReviewItem] = []
    /// Events already in the calendars around the recognized dates, for duplicate/conflict warnings.
    private(set) var existing: [ExistingEvent] = []
    private(set) var reviewError: String?
    /// Why an automatic add stopped at the review screen; empty in review mode.
    private(set) var reviewReasons: [ReviewReason] = []
    /// The review screen edits events that already exist in the calendar.
    private(set) var isEditingSaved = false

    let settings: AppSettings
    let calendarAccess: CalendarAccess
    let history: HistoryRecorder
    private let recognition = RecognitionService()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Identifies the current run, so a cancelled one can't touch the state of a newer one.
    @ObservationIgnored private var run = 0
    /// The history entry of the request on screen.
    @ObservationIgnored private var historyID: UUID?

    /// `true` while macOS may be showing the Keychain password prompt: the popover must not close.
    @ObservationIgnored var onKeychainAccess: ((Bool) -> Void)?
    /// Recognition started or stopped (the menu bar icon pulses meanwhile).
    @ObservationIgnored var onActivityChanged: ((Bool) -> Void)?
    /// A result (events or an error) is ready to be seen.
    @ObservationIgnored var onResultReady: (() -> Void)?

    init(settings: AppSettings, calendarAccess: CalendarAccess, history: HistoryRecorder) {
        self.settings = settings
        self.calendarAccess = calendarAccess
        self.history = history
    }

    var isRecognizing: Bool {
        stage != nil
    }

    var includedCount: Int {
        items.filter(\.isIncluded).count
    }

    var canSave: Bool {
        includedCount > 0 && items.allSatisfy { !$0.isIncluded || (!$0.draft.title.trimmed.isEmpty && $0.calendarID != nil) }
    }

    // MARK: Recognition

    func recognize() {
        guard !isRecognizing, case .input = phase else { return }
        guard settings.isProviderReady else {
            input.showError(String(localized: "Set up a model in Settings first."))
            return
        }
        guard let request = input.makeRequest(settings: settings) else { return }

        input.clearNotice()
        run += 1
        let thisRun = run
        let mode = settings.addMode
        let entryID = history.begin(request, mode: mode)
        historyID = entryID
        stage = .waitingForModel
        task = Task {
            do {
                let result = try await recognition.recognize(request, settings: settings) { stage in
                    guard self.run == thisRun else { return }
                    self.stage = stage
                }
                try Task.checkCancellation()
                guard self.run == thisRun else { return }
                stage = nil
                history.update(entryID) { entry in
                    entry.recognized = result.drafts
                    entry.analysis = result.analysis
                    entry.status = result.drafts.isEmpty ? .noEvents : .notAdded
                }
                handle(result.drafts, mode: mode)
                onResultReady?()
            } catch is CancellationError {
                // Normally cancelled by the user, and `cancelRecognition` already reset the state.
                if self.run == thisRun {
                    stage = nil
                }
            } catch {
                guard self.run == thisRun else { return }
                stage = nil
                history.update(entryID) { entry in
                    entry.status = .failed
                    entry.errorMessage = error.localizedDescription
                }
                input.showError(error.localizedDescription)
                onResultReady?()
            }
        }
    }

    func cancelRecognition() {
        if isRecognizing, let historyID {
            // A cancelled request isn't worth keeping.
            history.delete(historyID)
            self.historyID = nil
        }
        task?.cancel()
        task = nil
        run += 1
        stage = nil
    }

    /// Review mode, or automatic mode when anything needs a look, shows the review screen; otherwise
    /// the events are added right away.
    private func handle(_ drafts: [EventDraft], mode: AddMode) {
        guard !drafts.isEmpty else {
            phase = .input
            input.showInfo(String(localized: "No events found. Try adding details or an instruction."))
            return
        }
        let calendarID = calendarAccess.resolvedCalendarID(preferred: settings.defaultCalendarID)
        items = drafts.map { ReviewItem(draft: $0, calendarID: calendarID) }
        isEditingSaved = false
        loadExistingEvents()
        reviewError = nil
        reviewReasons = []

        if mode == .automatic {
            let reasons = AutoAddPolicy.reasonsToReview(
                drafts,
                existing: existing,
                capabilities: calendarAccess.calendar(withID: calendarID)?.capabilities
            )
            if reasons.isEmpty {
                save()
                if case .saved = phase { return }
            }
            reviewReasons = reasons
        }
        phase = .review
    }

    private func loadExistingEvents() {
        guard let first = items.map(\.draft.start).min(), let last = items.map(\.draft.end).max() else { return }
        let day: TimeInterval = 24 * 3600
        let editing = Set(items.compactMap(\.eventIdentifier))
        existing = calendarAccess.existingEvents(from: first.addingTimeInterval(-day), to: last.addingTimeInterval(day))
            .filter { !editing.contains($0.id) }
    }

    func backToInput() {
        if isEditingSaved, let saved = lastSaved {
            // Leaving the edit screen keeps the events as they were saved.
            phase = .saved(saved)
            isEditingSaved = false
            return
        }
        phase = .input
        items = []
        reviewReasons = []
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

    @ObservationIgnored private var lastSaved: [SavedEvent]?

    func save() {
        let included = items.filter { $0.isIncluded && $0.calendarID != nil }
        let writes = included.map { item in
            var draft = item.draft
            draft.title = draft.title.trimmed
            return CalendarAccess.EventWrite(draft: draft, calendarID: item.calendarID ?? "", eventIdentifier: item.eventIdentifier)
        }
        // Edited events that were unchecked are removed from the calendar.
        let removed = items.filter { !$0.isIncluded }.compactMap(\.eventIdentifier)
        do {
            let identifiers = try calendarAccess.save(writes)
            if !removed.isEmpty {
                try calendarAccess.removeEvents(withIdentifiers: removed)
            }
            let saved = zip(writes, identifiers).map { write, identifier in
                SavedEvent(
                    draft: write.draft,
                    calendarID: write.calendarID,
                    calendarTitle: calendarAccess.calendar(withID: write.calendarID)?.title ?? "",
                    eventIdentifier: identifier
                )
            }
            history.update(historyID) { entry in
                entry.saved = saved
                entry.status = saved.isEmpty ? .notAdded : .created
            }
            lastSaved = saved
            isEditingSaved = false
            phase = .saved(saved)
            items = []
            reviewReasons = []
            input.clear()
        } catch {
            reviewError = error.localizedDescription
        }
    }

    /// Opens the review screen for the events just added, to change them in place.
    func editSaved() {
        guard case .saved(let saved) = phase, !saved.isEmpty else { return }
        items = saved.map { ReviewItem(draft: $0.draft, calendarID: $0.calendarID, eventIdentifier: $0.eventIdentifier) }
        isEditingSaved = true
        reviewReasons = []
        reviewError = nil
        loadExistingEvents()
        phase = .review
    }

    func undo() {
        guard case .saved(let saved) = phase else { return }
        do {
            try calendarAccess.removeEvents(withIdentifiers: saved.compactMap(\.eventIdentifier))
            history.update(historyID) { entry in
                entry.status = .undone
                for index in entry.saved.indices {
                    entry.saved[index].removed = true
                }
            }
            lastSaved = nil
            phase = .input
            input.showInfo(String(localized: "The events were removed from your calendar."))
        } catch {
            input.showError(String(localized: "Couldn’t remove the events: \(error.localizedDescription)"))
            phase = .input
        }
    }

    func startOver() {
        lastSaved = nil
        historyID = nil
        phase = .input
        input.requestFocus()
    }

    func openCalendarApp() {
        if case .saved(let saved) = phase, saved.count == 1 {
            calendarAccess.openInCalendar(eventIdentifier: saved[0].eventIdentifier)
        } else {
            calendarAccess.openInCalendar(eventIdentifier: nil)
        }
    }

    /// "Repeat request" from the history: the text and the screenshots go back into the input.
    func restore(text: String?, images: [Data]) {
        cancelRecognition()
        phase = .input
        items = []
        input.clear()
        input.content.text = text ?? ""
        images.forEach(input.addImage)
        input.requestFocus()
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
