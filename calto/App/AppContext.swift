import AppKit

/// App-wide state shared by the menu bar item, the input popup and the settings window.
@MainActor
final class AppContext {
    let settings = AppSettings()
    let calendarAccess = CalendarAccess()

    func openSettings(_ tab: SettingsTab? = nil) {
        SettingsWindowController.show(tab: tab, context: self)
    }

    func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
