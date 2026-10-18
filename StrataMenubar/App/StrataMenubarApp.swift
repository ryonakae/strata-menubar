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
                library: container.modelLibrary,
                installer: container.modelInstaller,
                paths: container.paths,
                updater: container.updater
            )
        } label: {
            Image(container.serverManager.state.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                settingsStore: container.settingsStore,
                serverManager: container.serverManager,
                library: container.modelLibrary,
                installer: container.modelInstaller,
                paths: container.paths,
                draftState: container.settingsDraft,
                updater: container.updater
            )
        }
        .windowResizability(.contentMinSize)
    }
}
