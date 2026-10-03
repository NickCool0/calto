import AppKit

/// App-wide state shared by the menu bar item, the input popup, the history and the settings window.
@MainActor
final class AppContext {
    let settings: AppSettings
    let calendarAccess = CalendarAccess()
    let history: HistoryRecorder
    /// "Repeat request" in the history: puts the text and screenshots back into the popover.
    var repeatRequest: ((String?, [Data]) -> Void)?

    init() {
        settings = AppSettings()
        history = HistoryRecorder(settings: settings)
    }

    func openSettings(_ tab: SettingsTab? = nil) {
        SettingsWindowController.show(tab: tab, context: self)
    }

    func openHistory() {
        HistoryWindowController.show(context: self)
    }

    /// While the history window is open it takes the place of the popover (see `PopoverController`).
    var isHistoryOpen: Bool {
        HistoryWindowController.isOpen
    }

    func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
