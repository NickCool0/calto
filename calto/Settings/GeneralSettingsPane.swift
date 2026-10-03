import CaltoKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsPane: View {
    let context: AppContext
    @Bindable var settings: AppSettings

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var loginItemError: String?
    @State private var language = AppLanguage.selected
    @State private var confirmingClearHistory = false

    private var calendarAccess: CalendarAccess { context.calendarAccess }

    var body: some View {
        Form {
            Section("Language") {
                Picker("Interface language", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.title).tag(language)
                    }
                }
                .onChange(of: language) { _, newValue in
                    AppLanguage.selected = newValue
                }
                if language != AppLanguage.launchSelection {
                    HStack {
                        Text("The new language applies after calto restarts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart calto") {
                            AppLanguage.relaunch()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("Calendar") {
                LabeledContent("Access") {
                    HStack {
                        Text(calendarAccess.status.localizedDescription)
                            .foregroundStyle(calendarAccess.status == .fullAccess ? Color.secondary : Color.orange)
                        switch calendarAccess.status {
                        case .fullAccess:
                            EmptyView()
                        case .notDetermined:
                            Button("Grant Access") {
                                Task { await calendarAccess.requestAccess() }
                            }
                        case .writeOnly, .denied:
                            Button("Open Privacy Settings") {
                                context.openCalendarPrivacySettings()
                            }
                        }
                    }
                }
                if calendarAccess.status == .fullAccess {
                    LabeledContent("Calendars") {
                        Text(verbatim: "\(calendarAccess.accounts.reduce(0) { $0 + $1.calendars.count })")
                    }
                }
            }

            Section("Adding events") {
                Picker("Mode", selection: $settings.addMode) {
                    Text("Review before adding").tag(AddMode.review)
                    Text("Add automatically").tag(AddMode.automatic)
                }
                .pickerStyle(.radioGroup)
                Text("Automatic mode adds clear events right away, with Undo. If anything is unclear — the date, a conflict, a likely duplicate — the events are shown for review anyway. You can also switch the mode with the button at the bottom of the popover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("New events") {
                Picker("Calendar", selection: $settings.defaultCalendarID) {
                    Text("Calendar app’s default").tag(String?.none)
                    ForEach(calendarAccess.accounts) { account in
                        Section(account.title) {
                            ForEach(account.calendars) { calendar in
                                Label {
                                    Text(calendar.title)
                                } icon: {
                                    Image(nsImage: CalendarSwatch.image(for: calendar.color))
                                }
                                .tag(String?.some(calendar.id))
                            }
                        }
                    }
                }
                Picker("Reminder", selection: $settings.defaultReminderMinutes) {
                    Text("None").tag(Int?.none)
                    ForEach([0, 5, 10, 15, 30, 60, 120, 1440], id: \.self) { minutes in
                        Text(AlarmText.describe(EventAlarm(minutesBefore: minutes))).tag(Int?.some(minutes))
                    }
                }
                Picker("Duration when no end is given", selection: $settings.defaultDurationMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { minutes in
                        Text(Duration.seconds(Int64(minutes) * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
                            .tag(minutes)
                    }
                }
                Text("Used when the text doesn’t mention them. You can change everything before adding events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                LabeledContent("Open calto") {
                    Text(verbatim: HotKeyCombo.default.displayString)
                        .monospaced()
                }
                Text("You’ll be able to change the shortcut in a later version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Picker("Keep history", selection: $settings.historyRetention) {
                    Text("Off").tag(HistoryRetention.off)
                    Text("7 days").tag(HistoryRetention.week)
                    Text("30 days").tag(HistoryRetention.month)
                    Text("1 year").tag(HistoryRetention.year)
                    Text("Forever").tag(HistoryRetention.forever)
                }
                .onChange(of: settings.historyRetention) { _, _ in
                    context.history.applyRetention()
                }
                HStack {
                    Text("Your requests, small thumbnails of screenshots and the events created are stored only on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History…") {
                        confirmingClearHistory = true
                    }
                    .disabled(context.history.entries.isEmpty)
                }
            }
            .confirmationDialog("Clear the whole history?", isPresented: $confirmingClearHistory) {
                Button("Clear History", role: .destructive) {
                    context.history.deleteAll()
                }
            } message: {
                Text("Events in your calendars are not affected.")
            }

            Section("System") {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                        Text("Start calto automatically when you sign in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, enabled in
                    updateLoginItem(enabled)
                }
                if loginItemNeedsApproval {
                    HStack {
                        Text("Allow calto in Login Items to finish.")
                            .font(.caption)
                        Button("Open Login Items") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .controlSize(.small)
                    }
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .settingsPaneStyle()
    }

    private func updateLoginItem(_ enabled: Bool) {
        let service = SMAppService.mainApp
        guard enabled != (service.status == .enabled) else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItemNeedsApproval = service.status == .requiresApproval
    }
}
