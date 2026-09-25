import Carbon.HIToolbox
import CaltoKit

/// A system-wide shortcut. Carbon's `RegisterEventHotKey` is still the only public API for global
/// hotkeys: it works inside the App Sandbox and, unlike `NSEvent` global monitors, needs no
/// Accessibility permission.
final class GlobalHotKey {
    let combo: HotKeyCombo
    /// Non-nil when the shortcut could not be registered (usually because another app owns it).
    private(set) var registrationError: OSStatus?

    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let signature: OSType = 0x4341_4C54 // "CALT"

    init(combo: HotKeyCombo, action: @escaping () -> Void) {
        self.combo = combo
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        var status = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, context, &handlerRef)
        if status == noErr {
            let id = EventHotKeyID(signature: Self.signature, id: 1)
            status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        }
        registrationError = status == noErr ? nil : status
    }

    fileprivate func fire() {
        action()
    }
}

/// Carbon delivers hotkey events on the main thread through the application event target.
private nonisolated func hotKeyEventHandler(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        hotKey.fire()
    }
    return noErr
}
