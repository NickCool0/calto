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

/// Everything the popover shows: input (recognition runs in place) → review → saved.
@MainActor
@Observable
final class PopoverModel {
    enum Phase {
        case input
        case review
        case saved(count: Int, identifiers: [String])
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

    let settings: AppSettings
    let calendarAccess: CalendarAccess
    private let recognition = RecognitionService()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Identifies the current run, so a cancelled one can't touch the state of a newer one.
    @ObservationIgnored private var run = 0

    /// `true` while macOS may be showing the Keychain password prompt: the popover must not close.
    @ObservationIgnored var onKeychainAccess: ((Bool) -> Void)?
    /// Recognition started or stopped (the menu bar icon pulses meanwhile).
    @ObservationIgnored var onActivityChanged: ((Bool) -> Void)?
    /// A result (events or an error) is ready to be seen.
    @ObservationIgnored var onResultReady: (() -> Void)?

    init(settings: AppSettings, calendarAccess: CalendarAccess) {
        self.settings = settings
        self.calendarAccess = calendarAccess
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
        stage = .waitingForModel
        task = Task {
            do {
                let drafts = try await recognition.recognize(request, settings: settings) { [weak self] stage in
                    guard let self, self.run == thisRun else { return }
                    self.stage = stage
                }
                try Task.checkCancellation()
                guard self.run == thisRun else { return }
                stage = nil
                showReview(drafts)
                onResultReady?()
            } catch is CancellationError {
                // Normally cancelled by the user, and `cancelRecognition` already reset the state.
                if self.run == thisRun {
                    stage = nil
                }
            } catch {
                guard self.run == thisRun else { return }
                stage = nil
                input.showError(error.localizedDescription)
                onResultReady?()
            }
        }
    }

    func cancelRecognition() {
        task?.cancel()
        task = nil
        run += 1
        stage = nil
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
