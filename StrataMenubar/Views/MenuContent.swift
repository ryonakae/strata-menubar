import AppKit
import SwiftUI

struct MenuContent: View {
    let serverManager: ServerManager
    let settingsStore: SettingsStore
    let paths: AppPaths
    @Environment(\.openSettings) private var openSettings

    private var state: ServerState { serverManager.state }

    private var unappliedSettings: Bool {
        guard let info = state.runningInfo else { return false }
        return info.settings != settingsStore.settings
    }

    private var canRefresh: Bool {
        switch state {
        case .stopped, .external, .failed: true
        case .starting, .running, .stopping: false
        }
    }

    /// The page of whatever is actually listening: the running server's own port, never the saved settings.
    private var chatURL: URL? {
        switch state {
        case .running(let info): StrataEndpoint.chat(port: info.port)
        case .external(let info): StrataEndpoint.chat(port: info.port)
        case .stopped, .starting, .stopping, .failed: nil
        }
    }

    var body: some View {
        Text(state.statusText)
        if unappliedSettings {
            Text("Saved settings differ from the running server")
        }
        Divider()
        Button("Start Server") {
            Task { await serverManager.start(settings: settingsStore.settings) }
        }
        .disabled(!serverManager.canStart)
        Button("Stop Server") {
            Task { await serverManager.stop() }
        }
        .disabled(!serverManager.canStop)
        if unappliedSettings {
            Button("Stop and Apply Saved Settings") {
                Task { await serverManager.restart(settings: settingsStore.settings) }
            }
        }
        if canRefresh {
            Button("Check Port Again") {
                Task { await serverManager.refresh(port: settingsStore.settings.port) }
            }
        }
        Divider()
        Button("Open Chat") {
            if let chatURL {
                NSWorkspace.shared.open(chatURL)
            }
        }
        .disabled(chatURL == nil)
        Divider()
        Button("Open Server Log") { open(log: paths.serverLog) }
        Button("Open Engine Log") { open(log: paths.engineLog) }
        Button("Show Logs in Finder") {
            try? FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
            NSWorkspace.shared.open(paths.logs)
        }
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

    private func open(log: URL) {
        if FileManager.default.fileExists(atPath: log.path(percentEncoded: false)) {
            NSWorkspace.shared.open(log)
        } else {
            try? FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
            NSWorkspace.shared.open(paths.logs)
        }
    }
}

extension ServerState {
    var runningInfo: RunningInfo? {
        if case .running(let info) = self { return info }
        return nil
    }
}
