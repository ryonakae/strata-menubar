import Foundation

/// Wires the app's long-lived objects together once; views and the app delegate share them through here.
@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let paths = AppPaths.standard
    let settingsStore: SettingsStore
    let settingsDraft = SettingsDraftState()
    let serverManager: ServerManager
    let modelLibrary: ModelLibrary
    let modelInstaller: ModelInstaller

    private init() {
        let settingsStore = SettingsStore()
        let library = ModelLibrary(root: settingsStore.settings.strataDirectoryURL)
        let serverManager = ServerManager(
            launcher: PosixProcessLauncher(),
            probe: URLSessionHealthProbe(),
            planner: StrataLaunchPlanner(paths: paths)
        )
        // Setup's preparation must not run beside an engine, including one idle unload has paused and one whose stop
        // failed: anything but a server confirmed gone counts as running.
        let installer = ModelInstaller(launcher: PosixProcessLauncher(), paths: paths, library: library, serverIsRunning: {
            switch serverManager.state {
            case .stopped, .failed: serverManager.ownsProcess
            case .starting, .running, .stopping, .external: true
            }
        })
        library.ownedSetupGroup = { [weak installer] in installer?.processGroup }
        self.settingsStore = settingsStore
        modelLibrary = library
        self.serverManager = serverManager
        modelInstaller = installer
        serverManager.startMonitoring { settingsStore.settings.port }
    }
}
