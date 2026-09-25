import SwiftUI

@main
struct CaltoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app lives in the menu bar (LSUIElement); windows are managed by AppKit controllers.
        Settings {
            Text("Settings will appear in a later stage.")
                .padding(40)
        }
    }
}
