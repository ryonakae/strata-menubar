import AppKit
import SwiftUI

struct MenuContent: View {
    let serverManager: ServerManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(serverManager.state.statusText)
        Divider()
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Strata Menubar") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
