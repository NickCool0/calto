import AppKit
import Carbon.HIToolbox

/// The borderless popup under the menu bar icon. A menu bar app has no visible Edit menu, so the
/// standard editing shortcuts are routed here explicitly; ⌘V goes to `pasteHandler`, which decides
/// between images and text.
final class InputPanel: NSPanel {
    var pasteHandler: (() -> Void)?
    var closeHandler: (() -> Void)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc from anywhere in the popup, including while editing text.
    override func cancelOperation(_ sender: Any?) {
        closeHandler?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
            closeHandler?()
            return true
        }

        switch (key, flags) {
        case ("v", .command):
            if let pasteHandler {
                pasteHandler()
                return true
            }
        case ("w", .command):
            closeHandler?()
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

    /// Whether a text view in the popup has keyboard focus.
    var isEditingText: Bool {
        firstResponder is NSText
    }

    private func send(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: nil, from: self)
    }
}
