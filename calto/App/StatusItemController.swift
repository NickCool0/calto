import AppKit
import CaltoKit

/// Owns the menu bar icon and its menu. The menu is rebuilt every time it opens,
/// so it always reflects the current calendar access state.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let calendarAccess: CalendarAccess
    private let inputPanel: InputPanelController

    init(calendarAccess: CalendarAccess, inputPanel: InputPanelController) {
        self.calendarAccess = calendarAccess
        self.inputPanel = inputPanel
        super.init()

        let icon = NSImage(systemSymbolName: "calendar.badge.plus", accessibilityDescription: "calto")
        icon?.isTemplate = true
        statusItem.button?.image = icon

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(actionItem(String(localized: "Open calto…"), action: #selector(openInput)))
        menu.addItem(.separator())
        addCalendarItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Quit calto"), action: #selector(quit), keyEquivalent: "q"))
    }

    // MARK: Menu content

    private func addCalendarItems(to menu: NSMenu) {
        switch calendarAccess.status {
        case .fullAccess:
            menu.addItem(infoItem(String(localized: "Calendar access: granted")))
            menu.addItem(calendarsItem())
        case .notDetermined:
            menu.addItem(infoItem(String(localized: "Calendar access: not requested yet")))
            menu.addItem(actionItem(String(localized: "Grant Calendar Access…"), action: #selector(requestCalendarAccess)))
        case .writeOnly:
            menu.addItem(infoItem(String(localized: "Calendar access: add-only (full access required)")))
            menu.addItem(actionItem(String(localized: "Open Privacy Settings…"), action: #selector(openPrivacySettings)))
        case .denied:
            menu.addItem(infoItem(String(localized: "Calendar access: denied")))
            menu.addItem(actionItem(String(localized: "Open Privacy Settings…"), action: #selector(openPrivacySettings)))
        }
        if let error = calendarAccess.lastError {
            menu.addItem(infoItem(String(localized: "Could not request calendar access: \(error)")))
        }
    }

    private func calendarsItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        if calendarAccess.accounts.isEmpty {
            submenu.addItem(infoItem(String(localized: "No writable calendars")))
        }
        for account in calendarAccess.accounts {
            let header = account.capabilities.maxAlarms == 1
                ? String(localized: "\(account.title) — 1 reminder per event")
                : account.title
            submenu.addItem(.sectionHeader(title: header))
            for calendar in account.calendars {
                let item = NSMenuItem(title: calendar.title, action: nil, keyEquivalent: "")
                item.image = swatch(for: calendar.color)
                item.indentationLevel = 1
                submenu.addItem(item)
            }
        }

        let item = NSMenuItem(title: String(localized: "Calendars"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func actionItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func swatch(for color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
            .applying(NSImage.SymbolConfiguration(pointSize: 9, weight: .regular))
        return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    // MARK: Actions

    @objc private func openInput() {
        inputPanel.show()
    }

    @objc private func requestCalendarAccess() {
        // The system prompt belongs to the frontmost app; an agent app must activate itself first.
        NSApp.activate()
        Task {
            await calendarAccess.requestAccess()
        }
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
