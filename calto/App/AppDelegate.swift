import AppKit
import CaltoKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Created on first use (on the main actor), not in NSObject's initializer.
    private(set) lazy var context = AppContext()
    private var statusItemController: StatusItemController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let inputPanel = InputPanelController(context: context)
        let hotKey = GlobalHotKey(combo: .default) {
            inputPanel.toggle()
        }
        let statusItem = StatusItemController(context: context, inputPanel: inputPanel, hotKey: hotKey)
        inputPanel.anchor = { [weak statusItem] in
            statusItem?.buttonFrameOnScreen
        }
        self.hotKey = hotKey
        statusItemController = statusItem

        // Ask for calendar access right away on first launch instead of waiting for the first save.
        Task {
            await context.calendarAccess.requestAccessIfNeeded()
        }
    }
}
