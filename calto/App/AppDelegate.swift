import AppKit
import CaltoKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Created on first use (on the main actor), not in NSObject's initializer.
    private(set) lazy var context = AppContext()
    private var statusItemController: StatusItemController?
    private var hotKey: GlobalHotKey?
    private var terminationObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Remember the language this copy runs in, so Settings can tell when a relaunch is needed.
        _ = AppLanguage.launchSelection

        let popover = PopoverController(context: context)
        let hotKey = GlobalHotKey(combo: .default) {
            popover.toggle()
        }
        let statusItem = StatusItemController(context: context, popover: popover, hotKey: hotKey)
        popover.anchorButton = { [weak statusItem] in
            statusItem?.button
        }
        popover.onActivityChanged = { [weak statusItem] busy in
            statusItem?.setBusy(busy)
        }
        self.hotKey = hotKey
        statusItemController = statusItem
        registerHotKeyAfterPreviousCopyQuits()

        // Ask for calendar access right away on first launch instead of waiting for the first save.
        Task {
            await context.calendarAccess.requestAccessIfNeeded()
        }
    }

    /// After a relaunch (e.g. to switch the language) the previous copy may still hold the shortcut
    /// for a moment; register it again once that copy has quit.
    private func registerHotKeyAfterPreviousCopyQuits() {
        guard hotKey?.registrationError != nil, let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        guard !others.isEmpty else { return }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == bundleID else { return }
            MainActor.assumeIsolated {
                self?.hotKey?.register()
                if let observer = self?.terminationObserver {
                    NSWorkspace.shared.notificationCenter.removeObserver(observer)
                }
                self?.terminationObserver = nil
            }
        }
    }
}
