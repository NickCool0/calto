import AppKit
import CaltoKit
import SwiftUI

/// The floating input window, opened by a left click on the menu bar icon or the global hotkey.
final class InputPanelController {
    let model = InputModel()
    private lazy var panel = makePanel()

    func show() {
        if !panel.isVisible {
            positionOnActiveScreen()
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

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

    /// Opens on the screen with the mouse pointer, slightly above center.
    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.1
        ))
    }

    private func makePanel() -> InputPanel {
        let panel = InputPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "calto"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: InputView(model: model))
        panel.pasteHandler = { [weak self] in
            self?.handlePaste()
        }
        return panel
    }
}
