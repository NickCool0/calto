import SwiftUI

@main
struct CaltoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app lives in the menu bar (LSUIElement); its windows are managed by AppKit controllers.
        // SwiftUI needs a scene, so an empty Settings scene is declared and its ⌘, command is routed
        // to calto's own settings window.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.context.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
