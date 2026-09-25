import AppKit
import CaltoKit
import SwiftUI

/// The popover's single input field: plain text that also takes screenshots.
///
/// Since macOS 15.4 (enforced in macOS 27) the general pasteboard can be read silently only when the
/// access is "user originated and paste related": the `paste:` action sent by Edit ▸ Paste or ⌘V.
/// So images are read here, inside `paste(_:)`, and never from a key monitor, which the system treats
/// as a programmatic read.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    /// Changes whenever the popover opens; the field then takes keyboard focus.
    var focusToken: Int
    var minLines = 3
    var maxLines = 12
    var onPaste: (PasteboardContent) -> Void
    var onSubmit: () -> Void

    static let font = NSFont.preferredFont(forTextStyle: .title3)

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
        context.coordinator.text = $text
        textView.onPaste = onPaste
        textView.onSubmit = onSubmit
        textView.isEditable = isEditable
        textView.textColor = isEditable ? .labelColor : .secondaryLabelColor
        // Don't disturb text being composed with an input method (marked text).
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    /// Grows with the text between `minLines` and `maxLines`, then scrolls.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, let textView = scrollView.documentView as? NSTextView else { return nil }
        let lineHeight = ceil(Self.font.ascender - Self.font.descender + Self.font.leading)
        var used = lineHeight
        if let layoutManager = textView.textLayoutManager, let container = textView.textContainer {
            container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: layoutManager.documentRange)
            used = layoutManager.usageBoundsForTextContainer.height
        }
        let height = min(max(used, lineHeight * CGFloat(minLines)), lineHeight * CGFloat(maxLines))
        return CGSize(width: width, height: ceil(height))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var focusToken: Int?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Plain-text view whose Paste also accepts images and image files.
final class ComposerNSTextView: NSTextView {
    var onPaste: ((PasteboardContent) -> Void)?
    var onSubmit: (() -> Void)?

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType("public.heic"), NSPasteboard.PasteboardType("public.jpeg"),
    ]

    /// Adding image types keeps Edit ▸ Paste (and ⌘V) enabled when the pasteboard holds only a
    /// screenshot; a plain-text view would otherwise disable it and beep. Drops use the same list.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        for type in Self.imageTypes + [.fileURL] where !types.contains(type) {
            types.append(type)
        }
        return types
    }

    /// Runs for Edit ▸ Paste and ⌘V: a user-initiated paste, so reading the pasteboard is allowed.
    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        let pasteboard = NSPasteboard.general
        switch PasteboardClassifier.pasteKind(forTypes: (pasteboard.types ?? []).map(\.rawValue)) {
        case .text:
            super.paste(sender)
        case .images:
            onPaste?(PasteboardReader.read(pasteboard))
        case .files:
            let content = PasteboardReader.read(pasteboard)
            if case .imageFiles = content {
                onPaste?(content)
            } else {
                // Other files: paste their names as text, like any text field.
                super.paste(sender)
            }
        }
    }

    /// Drops of images and image files onto the text; text drops are inserted as usual.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .fileURL || Self.imageTypes.contains(type) {
            let content = PasteboardReader.read(pboard)
            switch content {
            case .images, .imageFiles:
                onPaste?(content)
                return true
            case .text, .unsupported, .empty:
                break
            }
        }
        return super.readSelection(from: pboard, type: type)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, flags.contains(.command) {
            onSubmit?()
            return
        }
        // Only reached when no menu handled ⌘V (the Edit menu normally does); still a paste action.
        if flags.intersection([.command, .shift, .option, .control]) == .command, event.charactersIgnoringModifiers == "v" {
            NSApp.sendAction(#selector(paste(_:)), to: self, from: self)
            return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        // Let SwiftUI re-measure the field as lines are added or removed.
        enclosingScrollView?.invalidateIntrinsicContentSize()
    }
}
