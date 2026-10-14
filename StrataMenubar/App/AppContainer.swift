import Foundation

/// Wires the app's long-lived objects together once; views and the app delegate share them through here.
@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let paths = AppPaths.standard
    let settingsStore: SettingsStore
    let serverManager: ServerManager

    private init() {
        settingsStore = SettingsStore()
        serverManager = ServerManager(
            launcher: PosixProcessLauncher(),
            probe: URLSessionHealthProbe(),
            planner: StrataLaunchPlanner(paths: paths)
        )
        let settingsStore = settingsStore
        serverManager.startMonitoring { settingsStore.settings.port }
    }
}
