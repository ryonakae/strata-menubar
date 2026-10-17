import SwiftUI

@main
struct StrataMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container = AppContainer.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                serverManager: container.serverManager,
                settingsStore: container.settingsStore,
                paths: container.paths
            )
        } label: {
            Image(container.serverManager.state.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settingsStore: container.settingsStore, serverManager: container.serverManager, draftState: container.settingsDraft)
        }
    }
}
