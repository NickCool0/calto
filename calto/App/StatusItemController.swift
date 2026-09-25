import AppKit
import CaltoKit

/// Owns the menu bar icon. A left click toggles the input popup; a right click (or ⌃-click)
/// shows the menu, which is rebuilt every time so it reflects the current state.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let context: AppContext
    private let inputPanel: InputPanelController
    private let hotKey: GlobalHotKey

    private var calendarAccess: CalendarAccess { context.calendarAccess }

    init(context: AppContext, inputPanel: InputPanelController, hotKey: GlobalHotKey) {
        self.context = context
        self.inputPanel = inputPanel
        self.hotKey = hotKey
        super.init()

        let icon = NSImage(systemSymbolName: "calendar.badge.plus", accessibilityDescription: "calto")
        icon?.isTemplate = true
        if let button = statusItem.button {
            button.image = icon
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menu.autoenablesItems = false
        menu.delegate = self

        inputPanel.visibilityChanged = { [weak self] visible in
            self?.statusItem.button?.highlight(visible)
        }
    }

    /// Where the popup should hang from; `nil` when the icon isn't on screen (e.g. hidden by the notch).
    var buttonFrameOnScreen: NSRect? {
        guard let button = statusItem.button, let window = button.window, window.isVisible else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // Attach the menu only for this click so a left click keeps opening the input window.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            inputPanel.toggle()
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let openItem = actionItem(String(localized: "Open calto"), action: #selector(openInput))
        if hotKey.registrationError == nil, let key = hotKey.combo.keyCharacter {
            openItem.keyEquivalent = key
            openItem.keyEquivalentModifierMask = modifierFlags(hotKey.combo.modifiers)
        }
        menu.addItem(openItem)
        if hotKey.registrationError != nil {
            menu.addItem(infoItem(String(localized: "Shortcut \(hotKey.combo.displayString) is taken by another app")))
        }
        menu.addItem(actionItem(String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ","))
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

    private func modifierFlags(_ modifiers: HotKeyCombo.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
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

    @objc private func openSettings() {
        inputPanel.hide(returnFocus: false)
        context.openSettings()
    }

    @objc private func requestCalendarAccess() {
        // The system prompt belongs to the frontmost app; an agent app must activate itself first.
        NSApp.activate()
        Task {
            await calendarAccess.requestAccess()
        }
    }

    @objc private func openPrivacySettings() {
        context.openCalendarPrivacySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
