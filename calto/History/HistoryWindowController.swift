import AppKit
import SwiftUI

/// The history window: a standard window (sidebar list, detail, toolbar), opened from the popover, the
/// menu bar menu or ⌘Y. While it is open, the menu bar icon and the shortcut bring it to the front
/// instead of opening the popover.
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: HistoryWindowController?

    static var isOpen: Bool {
        shared?.window?.isVisible ?? false
    }

    static func show(context: AppContext) {
        if shared == nil {
            shared = HistoryWindowController(context: context)
        }
        shared?.showWindow(nil)
    }

    static func close() {
        shared?.close()
    }

    private init(context: AppContext) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 900, height: 600)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = String(localized: "History")
        window.toolbarStyle = .unified
        window.setFrameAutosaveName("HistoryWindow")
        window.minSize = NSSize(width: 720, height: 420)
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: HistoryView(context: context))
        Task { await context.history.reload() }
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
