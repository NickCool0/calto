import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The system popover under the menu bar icon (arrow, Liquid Glass, animated resizing, closes on a
/// click elsewhere), opened by a click on the icon or the global hotkey. Its content is kept between
/// openings, as Apple's guidelines ask for popovers that close on their own.
final class PopoverController: NSObject, NSPopoverDelegate {
    let model: PopoverModel
    /// The menu bar button the popover points at.
    var anchorButton: (() -> NSStatusBarButton?)?

    private let context: AppContext
    private let popover = NSPopover()
    private var keyMonitor: Any?
    /// Stand-in anchor when the menu bar icon is hidden (behind the notch or by a menu bar manager).
    private var fallbackAnchor: NSWindow?

    init(context: AppContext) {
        self.context = context
        model = PopoverModel(settings: context.settings, calendarAccess: context.calendarAccess)
        super.init()

        let root = PopoverView(model: model, calendarAccess: context.calendarAccess, openSettings: { [weak self] tab in
            self?.openSettings(tab)
        })
        let hosting = NSHostingController(rootView: root)
        // The popover follows the SwiftUI content's size and animates when it changes.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    var isShown: Bool {
        popover.isShown
    }

    func toggle() {
        if popover.isShown {
            close()
        } else {
            show()
        }
    }

    func show() {
        NSApp.activate()
        if let button = anchorButton?(), let window = button.window, window.isVisible, window.frame.width > 0 {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            button.highlight(true)
        } else {
            let anchor = makeFallbackAnchor()
            if let view = anchor.contentView {
                popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
        }
        popover.contentViewController?.view.window?.makeKey()
        model.input.requestFocus()
        installKeyMonitor()
    }

    func close() {
        popover.performClose(nil)
    }

    // MARK: NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        anchorButton?()?.highlight(false)
        fallbackAnchor?.orderOut(nil)
        removeKeyMonitor()
    }

    // MARK: Keyboard

    /// ⌘V goes through the Edit menu to the focused text field, which can only paste text. Images are
    /// intercepted here first; Esc closes the popover from any control.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let isPaste = flags == .command && event.charactersIgnoringModifiers?.lowercased() == "v"
            let isEscape = flags.isEmpty && event.keyCode == UInt16(kVK_Escape)
            guard isPaste || isEscape else { return event }

            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.popover.isShown, event.window === self.popover.contentViewController?.view.window else {
                    return false
                }
                if isEscape {
                    self.close()
                    return true
                }
                return self.model.pasteImagesIfPossible()
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    // MARK: Private

    private func openSettings(_ tab: SettingsTab?) {
        close()
        context.openSettings(tab)
    }

    /// An invisible 1-pt window at the top center of the screen with the pointer.
    private func makeFallbackAnchor() -> NSWindow {
        let window = fallbackAnchor ?? {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.level = .statusBar
            window.isReleasedWhenClosed = false
            fallbackAnchor = window
            return window
        }()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        window.setFrameOrigin(NSPoint(x: visible.midX, y: visible.maxY - 1))
        window.orderFrontRegardless()
        return window
    }
}

extension PopoverModel {
    /// Pastes images only while the input is shown; returns whether the event was used.
    func pasteImagesIfPossible() -> Bool {
        guard case .input = phase else { return false }
        return input.pasteImages()
    }
}
