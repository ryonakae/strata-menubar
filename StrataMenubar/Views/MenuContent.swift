import AppKit
import SwiftUI

struct MenuContent: View {
    let serverManager: ServerManager
    let settingsStore: SettingsStore
    let paths: AppPaths
    @Environment(\.openSettings) private var openSettings

    private var state: ServerState { serverManager.state }
    private var settings: StrataSettings { settingsStore.settings }
    private let memory = MemoryBudget.current

    private var unappliedSettings: Bool {
        guard let info = state.runningInfo else { return false }
        return info.settings != settings
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
        modelMenu
        cacheMenu
        contextMenu
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
            let problems = StrataInstallation(root: settings.strataDirectoryURL).check(model: settings.model)
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

    // MARK: - Saved-value submenus (a choice is saved at once; a running server keeps its own values)

    private var modelMenu: some View {
        let installed = StrataInstallation(root: settings.strataDirectoryURL).installedModels()
        let current = installed.first { $0.tag == settings.model }
        return Menu("Model: \(current?.modelName ?? settings.model)") {
            if installed.isEmpty {
                Text("No strata-<model>.json in \(settings.strataDirectory)")
            } else {
                Picker("Model", selection: binding(\.model)) {
                    ForEach(installed) { model in
                        Text(model.modelName).tag(model.tag)
                    }
                    if current == nil {
                        Text("\(settings.model) (not installed)").tag(settings.model)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }

    private var cacheMenu: some View {
        var choices = memory.cacheRange.map(Double.init)
        if !choices.contains(settings.expertCacheGB) {
            choices.append(settings.expertCacheGB)
            choices.sort()
        }
        return Menu("Expert cache: \(RunConfig.gigabytes(settings.expertCacheGB)) GB") {
            Picker("Expert cache", selection: binding(\.expertCacheGB)) {
                ForEach(choices, id: \.self) { value in
                    Text("\(RunConfig.gigabytes(value)) GB").tag(value)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private var contextMenu: some View {
        var choices = ContextSteps.values
        if !choices.contains(settings.maxContext) {
            choices.append(settings.maxContext)
            choices.sort()
        }
        return Menu("Context: \(settings.maxContext)") {
            Picker("Context", selection: binding(\.maxContext)) {
                ForEach(choices, id: \.self) { value in
                    Text(String(value)).tag(value)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<StrataSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                var changed = settingsStore.settings
                changed[keyPath: keyPath] = newValue
                settingsStore.save(changed)
            }
        )
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
