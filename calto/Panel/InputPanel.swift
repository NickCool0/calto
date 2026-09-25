import AppKit
import Carbon.HIToolbox

/// The input window. A menu bar app has no visible Edit menu, so standard editing shortcuts are
/// routed here explicitly; ⌘V goes to `pasteHandler`, which decides between images and text.
final class InputPanel: NSPanel {
    var pasteHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
            orderOut(nil)
            return true
        }

        switch (key, flags) {
        case ("v", .command):
            if let pasteHandler {
                pasteHandler()
                return true
            }
        case ("w", .command):
            orderOut(nil)
            return true
        case ("x", .command) where send(#selector(NSText.cut(_:))),
             ("c", .command) where send(#selector(NSText.copy(_:))),
             ("a", .command) where send(#selector(NSText.selectAll(_:))),
             ("z", .command) where send(Selector(("undo:"))),
             ("z", [.command, .shift]) where send(Selector(("redo:"))):
            return true
        default:
            break
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Whether the text view being edited currently has keyboard focus.
    var isEditingText: Bool {
        firstResponder is NSText
    }

    private func send(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: nil, from: self)
    }
}
