import SwiftUI

@main
struct StrataMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container = AppContainer.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(serverManager: container.serverManager)
        } label: {
            Image(systemName: container.serverManager.state.symbolName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
