import AppKit
import SwiftUI

struct MenuContent: View {
    let serverManager: ServerManager
    let settingsStore: SettingsStore
    let library: ModelLibrary
    let paths: AppPaths
    @Environment(\.openSettings) private var openSettings

    private var state: ServerState { serverManager.state }
    private var settings: StrataSettings { settingsStore.settings }

    private var unappliedSettings: Bool {
        guard let info = state.runningInfo else { return false }
        return info.settings.effective != settings.effective
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
        settingsSection
        Divider()
        Button("Start Server") {
            Task { await serverManager.start(settings: settings) }
        }
        .disabled(!serverManager.canStart)
        Button("Stop Server") {
            Task { await serverManager.stop() }
        }
        .disabled(!serverManager.canStop)
        if unappliedSettings {
            // A launch that is bound to fail must not take a working server down with it.
            let problems = library.launchProblems(for: settings.model)
            Button("Stop and Apply Saved Settings") {
                Task { await serverManager.restart(settings: settings) }
            }
            .disabled(!problems.isEmpty)
            if let problem = problems.first {
                Text("Cannot apply: \(problem)")
            }
        }
        if canRefresh {
            Button("Check Port Again") {
                Task { await serverManager.refresh(port: settings.port) }
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
        Button("Settings…") { showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Strata Menubar") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Saved values (read-only; the settings window changes them)

    /// The saved values, which the next start uses. A tuning value left to the engine or setup is listed only while
    /// the running server has another one, so that the difference is visible.
    private var settingsSection: some View {
        let modelName = library.installed.first { $0.tag == settings.model }?.modelName
        let saved = SettingsSummary.rows(for: settings, modelName: modelName)
        let running = state.runningInfo.map { SettingsSummary.rows(for: $0.settings, modelName: $0.model) }
        return Section("Settings for the next start") {
            ForEach(saved) { row in
                let runningValue = running?.first { $0.label == row.label }?.value
                let differs = runningValue != nil && runningValue != row.value
                if !row.isDefault || differs {
                    Button("\(row.label): \(row.value)" + (differs ? " (running: \(runningValue ?? ""))" : "")) { showSettings() }
                }
            }
        }
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
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
