import AppKit
import CaltoKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Created on first use (on the main actor), not in NSObject's initializer.
    private(set) lazy var context = AppContext()
    private var statusItemController: StatusItemController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let popover = PopoverController(context: context)
        let hotKey = GlobalHotKey(combo: .default) {
            popover.toggle()
        }
        let statusItem = StatusItemController(context: context, popover: popover, hotKey: hotKey)
        popover.anchorButton = { [weak statusItem] in
            statusItem?.button
        }
        self.hotKey = hotKey
        statusItemController = statusItem

        // Ask for calendar access right away on first launch instead of waiting for the first save.
        Task {
            await context.calendarAccess.requestAccessIfNeeded()
        }
    }
}
