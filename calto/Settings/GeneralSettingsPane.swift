import CaltoKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsPane: View {
    let context: AppContext

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
