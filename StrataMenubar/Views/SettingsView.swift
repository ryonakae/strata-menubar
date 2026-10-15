import AppKit
import SwiftUI

/// Edits a draft of the saved settings. Apply saves it; the saved values apply at the next start, and a running
/// server keeps the values it was started with until an explicit restart. Closing with unapplied changes asks first.
struct SettingsView: View {
    let settingsStore: SettingsStore
    let serverManager: ServerManager
    let draftState: SettingsDraftState

    private let memory = MemoryBudget.current

    @State private var draft: StrataSettings
    @State private var portText: String
    @State private var installationProblems: [String]?
    @State private var packToInstall: String = StrataModelCatalog.packs[0].name
    @State private var copied = false

    init(settingsStore: SettingsStore, serverManager: ServerManager, draftState: SettingsDraftState) {
        self.settingsStore = settingsStore
        self.serverManager = serverManager
        self.draftState = draftState
        let settings = settingsStore.settings
        _draft = State(initialValue: settings)
        _portText = State(initialValue: String(settings.port))
    }

    private var saved: StrataSettings { settingsStore.settings }
    /// A port field that does not parse is unapplied work too: it must be revertable and asked about.
    private var isDirty: Bool { draft != saved || !portIsNumber }
    private var running: RunningInfo? { serverManager.state.runningInfo }
    private var installed: [InstalledModel] { StrataInstallation(root: draft.strataDirectoryURL).installedModels() }
    private var portIsNumber: Bool { Int(portText.trimmingCharacters(in: .whitespaces)) != nil }
    private var issues: [SettingsIssue] {
        draft.validate(memory: memory) + (portIsNumber ? [] : [.error("The port must be a number.")])
    }
    private var hasErrors: Bool { issues.contains { $0.severity == .error } }
    private var launchProblems: [String] { installationProblems ?? [] }

    var body: some View {
        Form {
            installationSection
            modelSection
            memorySection
            runningSection
            installSection
            applySection
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .background(WindowCloseGuard(isDirty: isDirty, discard: revert))
        .onAppear {
            checkInstallation()
            draftState.discard = { revert() }
            draftState.isDirty = isDirty
        }
        .onDisappear {
            draftState.isDirty = false
        }
        .onChange(of: isDirty) { _, dirty in
            draftState.isDirty = dirty
        }
        .onChange(of: draft.strataDirectory) { checkInstallation() }
        .onChange(of: draft.model) { checkInstallation() }
        .onChange(of: portText) { _, text in
            if let port = Int(text.trimmingCharacters(in: .whitespaces)) {
                draft.port = port
            }
        }
        .onChange(of: settingsStore.settings) { previous, current in
            // A choice made in the menu shows up here unless the user is in the middle of editing.
            if draft == previous {
                load(current)
            }
        }
    }

    // MARK: - Sections

    private var installationSection: some View {
        Section("Strata installation") {
            TextField("Strata directory", text: $draft.strataDirectory)
            HStack(alignment: .top) {
                installationStatus
                Spacer()
                Button("Check") { checkInstallation() }
            }
            Text("The directory must contain Strata's `.venv`, `serve/server.py` and a `strata-<model>.json` from a finished setup. "
                + "This app never installs, updates or edits anything there.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        Section("Model") {
            if installed.isEmpty {
                Text("No strata-<model>.json found in the Strata directory.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: $draft.model) {
                    ForEach(installed) { model in
                        Text("\(model.modelName) (\(model.configURL.lastPathComponent))").tag(model.tag)
                    }
                    if !installed.contains(where: { $0.tag == draft.model }) {
                        Text("\(draft.model) (not installed)").tag(draft.model)
                    }
                }
            }
        }
    }

    private var memorySection: some View {
        Section("Memory and context") {
            Slider(value: $draft.expertCacheGB, in: Double(memory.cacheRange.lowerBound)...Double(memory.cacheRange.upperBound), step: 1) {
                Text("Expert cache: \(RunConfig.gigabytes(draft.expertCacheGB)) GB")
            } minimumValueLabel: {
                Text("1")
            } maximumValueLabel: {
                Text("\(memory.cacheRange.upperBound)")
            }
            Slider(value: contextSlider, in: 0...Double(ContextSteps.values.count - 1), step: 1) {
                Text("Context: \(draft.maxContext)")
            } minimumValueLabel: {
                Text(String(ContextSteps.values[0]))
            } maximumValueLabel: {
                Text(String(ContextSteps.values[ContextSteps.values.count - 1]))
            }
            TextField("Port", text: $portText)
            ForEach(issues) { issue in
                issueLabel(issue.message, isError: issue.severity == .error)
            }
            Text("The expert cache (STRATA_METAL_ARENA_GB) is only the arena for the most-used experts, not a limit on Strata's "
                + "total memory: on this Mac a 5 GB cache gave the engine a footprint of about 13 GB at start. A fixed value is "
                + "never shrunk automatically when memory runs short. \"About 16 GB overall\" is an operating goal, not a limit "
                + "this app enforces. Values are saved as you set them; warnings only say what has not worked here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var runningSection: some View {
        Section("Running server") {
            if let running {
                LabeledContent("Started with", value: Self.describe(running.settings))
                if isDirty {
                    Text("Apply the changes above to save them; \"Apply and Restart Server\" also restarts with them.")
                        .foregroundStyle(.secondary)
                } else if running.settings != saved {
                    HStack {
                        Text("The saved settings differ. They apply at the next start, or now:")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Stop and Apply Saved Settings") {
                            let settings = saved
                            Task { await serverManager.restart(settings: settings) }
                        }
                        .disabled(saved.hasErrors || !launchProblems.isEmpty)
                    }
                }
            } else {
                Text("Not running. Saved settings apply at the next start.")
                    .foregroundStyle(.secondary)
            }
            Text("Pi reads this server at http://127.0.0.1:\(String(draft.port))/v1 with contextWindow 8192 in "
                + "~/Dev/local/.pi/models.json, and the model id there must equal the server's model name (what /v1/models "
                + "reports). After changing the port, the context or the model, edit that file by hand; this app never touches it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var installSection: some View {
        let pack = StrataModelCatalog.packs.first { $0.name == packToInstall } ?? StrataModelCatalog.packs[0]
        let command = SetupCommand.make(strataDirectory: draft.strataDirectory, model: pack.name)
        return Section("Install another model") {
            Picker("Pack", selection: $packToInstall) {
                ForEach(StrataModelCatalog.packs) { pack in
                    Text(pack.name + (pack.isInstalled(among: installed) ? " (installed)" : "")).tag(pack.name)
                }
            }
            Text(Self.describe(pack))
                .font(.callout)
            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button(copied ? "Copied" : "Copy Command") { copy(command) }
            }
            Text("Run it in a terminal; setup downloads the model (\(RunConfig.gigabytes(pack.downloadGB)) GB), prepares it and writes "
                + "strata-\(pack.tag).json. --no-start keeps setup from starting its own server, so you can start the model from "
                + "this app afterwards. Sizes are from Strata's docs for a Mac; this Mac has \(memory.physicalMemoryGiB) GiB.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var applySection: some View {
        Section {
            HStack {
                Button("Revert") { revert() }
                    .disabled(!isDirty)
                Spacer()
                if let running {
                    Button("Apply and Restart Server") {
                        apply()
                        let settings = draft
                        Task { await serverManager.restart(settings: settings) }
                    }
                    .disabled(hasErrors || !launchProblems.isEmpty || (!isDirty && running.settings == saved))
                }
                Button("Apply") { apply() }
                    .disabled(!isDirty || hasErrors)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Applied settings are used at the next start. The menu bar's Model, Expert cache and Context submenus save "
                + "at once without this window.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var installationStatus: some View {
        if let installationProblems {
            if installationProblems.isEmpty {
                Label("Installation looks complete", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(installationProblems, id: \.self) { problem in
                        issueLabel(problem, isError: true)
                    }
                }
            }
        } else {
            Text("Not checked yet")
                .foregroundStyle(.secondary)
        }
    }

    private func issueLabel(_ message: String, isError: Bool) -> some View {
        Label(message, systemImage: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(isError ? Color.red : Color.orange)
            .font(.callout)
    }

    // MARK: - Draft handling

    /// The slider position is derived from the draft, so that Revert can restore a saved context that is not a step.
    private var contextSlider: Binding<Double> {
        Binding(
            get: { Double(ContextSteps.nearestIndex(to: draft.maxContext)) },
            set: { draft.maxContext = ContextSteps.values[Int($0)] }
        )
    }

    private func apply() {
        guard isDirty, !hasErrors else { return }
        draft.strataDirectory = draft.strataDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.save(draft)
    }

    private func revert() {
        load(saved)
    }

    private func load(_ settings: StrataSettings) {
        draft = settings
        portText = String(settings.port)
    }

    private func checkInstallation() {
        installationProblems = StrataInstallation(root: draft.strataDirectoryURL).check(model: draft.model)
    }

    private func copy(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private static func describe(_ settings: StrataSettings) -> String {
        "model \(settings.model), cache \(RunConfig.gigabytes(settings.expertCacheGB)) GB, context \(settings.maxContext), port \(settings.port)"
    }

    private static func describe(_ pack: ModelPack) -> String {
        var parts = [pack.note, "GPU maps \(RunConfig.gigabytes(pack.mappedFileGB)) GB"]
        if let needs = pack.needsAboutGB {
            parts.append("needs about \(RunConfig.gigabytes(needs)) GB")
        } else {
            parts.append("streams from the SSD")
        }
        parts.append("recommended from \(pack.recommendedFromGB) GB")
        return parts.joined(separator: " · ")
    }
}
