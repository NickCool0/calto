import AppKit
import CaltoKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let inputPanel = InputPanelController()
        let hotKey = GlobalHotKey(combo: .default) {
            inputPanel.show()
        }
        self.hotKey = hotKey
        statusItemController = StatusItemController(
            calendarAccess: CalendarAccess(),
            inputPanel: inputPanel,
            hotKey: hotKey
        )
    }
}
