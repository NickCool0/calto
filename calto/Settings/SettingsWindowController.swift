import AppKit
import SwiftUI

/// The settings window. Created by AppKit rather than a SwiftUI `Window` scene so it gets
/// `.fullSizeContentView` (Liquid Glass chrome) and can be opened from the menu bar popup.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    static func show(tab: SettingsTab? = nil, context: AppContext) {
        if let tab {
            SettingsNavigation.shared.selectedTab = tab
        }
        if shared == nil {
            shared = SettingsWindowController(context: context)
        }
        shared?.showWindow(nil)
    }

    private init(context: AppContext) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 720, height: 560)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = String(localized: "calto Settings")
        window.toolbarStyle = .automatic
        window.setFrameAutosaveName("SettingsWindow")
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SettingsView(context: context))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        NSApp.unhide(nil)
        let wasVisible = window?.isVisible ?? false
        super.showWindow(sender)
        if !wasVisible {
            AppActivationPolicy.enter()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}

/// A menu bar app has no Dock icon; while a regular window is open it temporarily becomes a regular
/// app so the window can take focus and appear in ⌘Tab.
enum AppActivationPolicy {
    private static var openWindows = 0

    static func enter() {
        openWindows += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func leave() {
        openWindows = max(0, openWindows - 1)
        guard openWindows == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
