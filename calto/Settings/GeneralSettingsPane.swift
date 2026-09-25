import CaltoKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsPane: View {
    let context: AppContext
    @Bindable var settings: AppSettings

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var loginItemError: String?

    private var calendarAccess: CalendarAccess { context.calendarAccess }

    var body: some View {
        Form {
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
