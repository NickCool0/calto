import AppKit
import CaltoKit
import SwiftUI

/// Shows the input popup under the menu bar icon, like a menu bar popover: it opens from a click on
/// the icon or the global hotkey and closes on Esc or a click anywhere else. Content is kept between
/// openings.
final class InputPanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 560, height: 440)
    static let cornerRadius: CGFloat = 16

    let model = InputModel()
    /// Screen frame of the menu bar button; the popup hangs below it.
    var anchor: (() -> NSRect?)?
    var visibilityChanged: ((Bool) -> Void)?

    private let context: AppContext
    private lazy var panel = makePanel()
    /// When a click on the menu bar icon closes the popup (by taking focus away), the same click
    /// must not reopen it.
    private var lastAutoHide = Date.distantPast

    init(context: AppContext) {
        self.context = context
        super.init()
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else if Date.now.timeIntervalSince(lastAutoHide) > 0.3 {
            show()
        }
    }

    func show() {
        position()
        // Closing with Esc hides the app to hand focus back; bring it back first.
        NSApp.unhide(nil)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()
        visibilityChanged?(true)
    }

    /// - Parameter returnFocus: give focus back to the app the user was in (Esc, the hotkey, a click
    ///   on the icon). Not needed when focus already moved elsewhere or another calto window opens.
    func hide(returnFocus: Bool = true) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        visibilityChanged?(false)
        let otherWindowOpen = NSApp.windows.contains { $0 !== panel && $0.isVisible && $0.canBecomeMain }
        if returnFocus && !otherWindowOpen {
            NSApp.hide(nil)
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        lastAutoHide = .now
        hide(returnFocus: false)
    }

    // MARK: Private

    private func handlePaste() {
        let content = PasteboardReader.read()
        switch content {
        case .images, .imageFiles:
            model.add(content)
        case .text, .unsupported, .empty:
            if panel.isEditingText {
                // Let the focused text view paste the way it normally does.
                _ = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: panel)
            } else {
                model.add(content)
            }
        }
    }

    private func openSettings(_ tab: SettingsTab?) {
        hide(returnFocus: false)
        context.openSettings(tab)
    }

    /// Hangs the popup under the menu bar icon, kept inside the visible part of that screen.
    private func position() {
        let size = Self.size
        let anchorRect = anchor?() ?? fallbackAnchor()
        let screen = NSScreen.screens.first { $0.frame.intersects(anchorRect) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let margin: CGFloat = 8
        var x = anchorRect.midX - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        let top = min(anchorRect.minY, visible.maxY) - 6
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: false)
    }

    /// Top center of the screen with the pointer, if the icon is hidden (e.g. behind the notch).
    private func fallbackAnchor() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return NSRect(x: visible.midX, y: visible.maxY, width: 0, height: 0)
    }

    private func makePanel() -> InputPanel {
        let panel = InputPanel(size: Self.size)
        panel.delegate = self
        let view = InputView(
            model: model,
            settings: context.settings,
            calendarAccess: context.calendarAccess,
            actions: InputView.Actions(
                openSettings: { [weak self] tab in self?.openSettings(tab) },
                openCalendarPrivacy: { [weak self] in self?.context.openCalendarPrivacySettings() },
                close: { [weak self] in self?.hide() }
            )
        )
        // Behind-window blur like a menu bar popover; SwiftUI materials only blend within the window.
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        panel.contentView = background
        panel.pasteHandler = { [weak self] in self?.handlePaste() }
        panel.closeHandler = { [weak self] in self?.hide() }
        return panel
    }

    /// A stretchable rounded-rectangle mask for the blurred background.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { @Sendable rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
