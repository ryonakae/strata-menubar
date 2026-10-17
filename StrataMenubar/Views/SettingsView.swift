import AppKit
import SwiftUI

/// Edits a draft of the saved settings. Apply saves it; the saved values apply at the next start, and a running
/// server keeps the values it was started with until an explicit restart. Closing with unapplied changes asks first.
struct SettingsView: View {
    let settingsStore: SettingsStore
    let serverManager: ServerManager
    let library: ModelLibrary
    let installer: ModelInstaller
    let paths: AppPaths
    let draftState: SettingsDraftState

    private let memory = MemoryBudget.current

    @State private var draft: StrataSettings
    @State private var portText: String
    @State private var installationProblems: [String]?
    @State private var baseFacts: BaseConfigFacts?

    init(
        settingsStore: SettingsStore,
        serverManager: ServerManager,
        library: ModelLibrary,
        installer: ModelInstaller,
        paths: AppPaths,
        draftState: SettingsDraftState
    ) {
        self.settingsStore = settingsStore
        self.serverManager = serverManager
        self.library = library
        self.installer = installer
        self.paths = paths
        self.draftState = draftState
        let settings = settingsStore.settings
        _draft = State(initialValue: settings)
        _portText = State(initialValue: String(settings.port))
    }

    private var saved: StrataSettings { settingsStore.settings }
    /// A port field that does not parse is unapplied work too: it must be revertable and asked about.
    private var isDirty: Bool { draft != saved || !portIsNumber }
    private var running: RunningInfo? { serverManager.state.runningInfo }
    /// The saved directory is watched; a directory typed but not yet applied is read afresh instead, and nothing is
    /// downloaded into or deleted from it until it is applied.
    private var usesLibrary: Bool { draft.strataDirectoryURL.path(percentEncoded: false) == library.root.path(percentEncoded: false) }
    private var listing: (installed: [InstalledModel], packs: [ModelLibrary.PackStatus]) {
        usesLibrary ? (library.installed, library.packs) : ModelLibrary.scan(root: draft.strataDirectoryURL)
    }
    private var portIsNumber: Bool { Int(portText.trimmingCharacters(in: .whitespaces)) != nil }
    private var issues: [SettingsIssue] {
        draft.validate(memory: memory, base: baseFacts) + (portIsNumber ? [] : [.error("The port must be a number.")])
    }
    private var hasErrors: Bool { issues.contains { $0.severity == .error } }
    private var launchProblems: [String] { installationProblems ?? [] }

    var body: some View {
        Form {
            installationSection
            modelsSection
            memorySection
            serverSection
            engineSection
            runningSection
            applySection
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .background(WindowCloseGuard(isDirty: isDirty, discard: revert))
        .onAppear {
            checkInstallation()
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
        .onChange(of: library.packs) {
            // A download, a deletion or a setup in a terminal changes what the selected model needs.
            if usesLibrary {
                updateInstallationProblems()
            }
        }
        .onChange(of: portText) { _, text in
            if let port = Int(text.trimmingCharacters(in: .whitespaces)) {
                draft.port = port
            }
        }
        .onChange(of: settingsStore.settings) { previous, current in
            // A change saved elsewhere shows up here unless the user is in the middle of editing.
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
            Text("The directory must contain Strata's `.venv`, `serve/server.py` and `setup.py`. Models are downloaded and prepared "
                + "by Strata's own setup from the Models section; this app does not install or update Strata itself.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var modelsSection: some View {
        let listing = listing
        let downloaded = listing.packs.filter { $0.state == .downloaded }.map(\.pack)
        let known = listing.installed.contains { $0.tag == draft.model } || downloaded.contains { $0.tag == draft.model }
        return Section("Models") {
            if listing.installed.isEmpty, downloaded.isEmpty {
                Text("No model is installed or downloaded in the Strata directory yet. Download one below.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: $draft.model) {
                    ForEach(listing.installed) { model in
                        Text("\(model.modelName) (\(model.configURL.lastPathComponent))").tag(model.tag)
                    }
                    ForEach(downloaded) { pack in
                        Text("\(pack.name) (downloaded; prepared at the first start)").tag(pack.tag)
                    }
                    if !known {
                        Text("\(draft.model) (not installed)").tag(draft.model)
                    }
                }
            }
            if !usesLibrary {
                Text("Apply the Strata directory to download or delete models in it.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            ForEach(listing.packs) { status in
                packRow(status)
            }
            HStack(alignment: .top) {
                Text(freeSpaceText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Setup Log") { paths.openLog(paths.setupLog) }
            }
        }
    }

    private func packRow(_ status: ModelLibrary.PackStatus) -> some View {
        let pack = status.pack
        let job = installer.job?.pack == pack ? installer.job : nil
        let downloadBlocker = status.downloadBlocker(setupRunning: installer.ownsProcess, freeBytes: library.freeBytes, memory: memory)
        let deleteBlocker = deletionBlocker(for: status)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(pack.name)
                    .fontWeight(.semibold)
                Text(status.stateText(job: installer.job, lastOutcome: installer.lastOutcome))
                    .foregroundStyle(.secondary)
                Spacer()
                if let job {
                    Button("Cancel") { Task { await installer.cancel() } }
                        .disabled(job.cancelRequested)
                } else {
                    if status.canDownload {
                        Button(status.state == .notDownloaded ? "Download" : "Resume") {
                            Task { await installer.download(pack) }
                        }
                        .disabled(!usesLibrary || downloadBlocker != nil)
                    }
                    if status.state != .notDownloaded {
                        Button("Delete…") { confirmAndDelete(status) }
                            .disabled(!usesLibrary || deleteBlocker != nil)
                    }
                }
            }
            if let job {
                if job.phase == .downloading, let progress = job.progress {
                    ProgressView(value: progress.fraction)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
            if job != nil || installer.lastOutcome?.pack == pack, let line = installer.statusLine {
                Text(line)
                    .font(.footnote)
            }
            Text(Self.describe(pack, memory: memory))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if usesLibrary, job == nil {
                if status.canDownload, let downloadBlocker {
                    issueLabel("Cannot download: \(downloadBlocker).", isError: false)
                }
                if status.state != .notDownloaded, let deleteBlocker {
                    issueLabel("Cannot delete: \(deleteBlocker).", isError: false)
                }
            }
        }
    }

    private var memorySection: some View {
        Section("Memory and context") {
            Toggle("Size the expert cache automatically", isOn: $draft.autoExpertCache)
            Slider(value: $draft.expertCacheGB, in: Double(memory.cacheRange.lowerBound)...Double(memory.cacheRange.upperBound), step: 1) {
                Text("Expert cache: \(RunConfig.gigabytes(draft.expertCacheGB)) GB")
            } minimumValueLabel: {
                Text("1")
            } maximumValueLabel: {
                Text("\(memory.cacheRange.upperBound)")
            }
            .disabled(draft.autoExpertCache)
            Picker("Keep free for macOS", selection: $draft.keepFreeGB) {
                Text("Engine default (\(RunConfig.gigabytes(EngineDefaults.keepFreeGB(memory: memory))) GB on this Mac)").tag(Int?.none)
                ForEach(choices(Array(memory.cacheRange), including: draft.keepFreeGB), id: \.self) { value in
                    Text("\(value) GB").tag(Int?.some(value))
                }
            }
            .disabled(!draft.autoExpertCache)
            Slider(value: contextSlider, in: 0...Double(ContextSteps.values.count - 1), step: 1) {
                Text("Context: \(draft.maxContext)")
            } minimumValueLabel: {
                Text(String(ContextSteps.values[0]))
            } maximumValueLabel: {
                Text(String(ContextSteps.values[ContextSteps.values.count - 1]))
            }
            Picker("Prompt chunk", selection: $draft.promptChunk) {
                Text(promptChunkAutoLabel).tag(Int?.none)
                ForEach(choices(PromptChunkSteps.values, including: draft.promptChunk), id: \.self) { value in
                    Text(String(value)).tag(Int?.some(value))
                }
            }
            Text("Automatic: the engine sizes the expert arena from the memory macOS can give and keeps 7 GB or 15% of the RAM "
                + "for macOS, whichever is more (Strata's docs/MAC.md). Fixed: the cache (STRATA_METAL_ARENA_GB) is only the arena "
                + "for the most-used experts, not a limit on Strata's total memory: on a 32 GiB Mac a 5 GB cache gave the engine a "
                + "footprint of about 13 GB at start, and a fixed value is never shrunk when memory runs short. The prompt chunk "
                + "(STRATA_METAL_PROMPT_CHUNK) defaults to 2048 for a resident model and, when the experts stream, to 4096 from "
                + "96 GiB of RAM and 1024 below. Values are saved as you set them; warnings only say what has not worked.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var serverSection: some View {
        Section("Server") {
            TextField("Port", text: $portText)
            Picker("Unload the model after", selection: $draft.idleUnloadMinutes) {
                ForEach(choices(IdleUnloadSteps.minutes, including: draft.idleUnloadMinutes), id: \.self) { minutes in
                    Text(SettingsSummary.idleUnload(minutes)).tag(minutes)
                }
            }
            Toggle("Fit max_tokens to the remaining context", isOn: $draft.fitMaxTokens)
            Text("Idle unload ends the engine process after that long without requests and starts it again for the next one, "
                + "which then takes a few seconds; the menu shows the model as unloaded meanwhile. Fit max_tokens clamps a "
                + "request's max_tokens to what fits in the context instead of answering 400; a prompt that is itself longer "
                + "than the context is still rejected.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var engineSection: some View {
        Section("Engine") {
            Picker("Verify window (--spec)", selection: $draft.specWindow) {
                Text(specAsSetUpLabel).tag(Int?.none)
                ForEach(choices(Array(SpecWindow.range), including: draft.specWindow), id: \.self) { value in
                    Text(String(value)).tag(Int?.some(value))
                }
            }
            if let baseFacts, !baseFacts.hasMTP {
                Text("This model's config has no MTP draft layer (--mtp); --spec has no effect until setup adds one.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Text("The verify window is how many tokens the MTP drafter proposes per check. Setup writes 2, or 3 for a streaming "
                + "Mac that keeps the draft layer; 2 measured best on mixed text and 5 or more slower (Strata's docs/MAC.md).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var runningSection: some View {
        Section("Running server") {
            if let running {
                LabeledContent("Started with", value: SettingsSummary.describe(running.settings, modelName: running.model))
                if isDirty {
                    Text("Apply the changes above to save them; \"Apply and Restart Server\" also restarts with them.")
                        .foregroundStyle(.secondary)
                } else if running.settings.effective != saved.effective {
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
            Text("Clients reach the server at http://127.0.0.1:\(String(draft.port))/v1 and address the model by the name "
                + "/v1/models reports. After changing the port or the model, update them yourself; this app does not touch them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var applySection: some View {
        Section {
            ForEach(issues) { issue in
                issueLabel(issue.message, isError: issue.severity == .error)
            }
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
                    .disabled(hasErrors || !launchProblems.isEmpty || (!isDirty && running.settings.effective == saved.effective))
                }
                Button("Apply") { apply() }
                    .disabled(!isDirty || hasErrors)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Applied settings are used at the next start. The menu bar lists them; it does not change them.")
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

    private var promptChunkAutoLabel: String {
        if let chunk = EngineDefaults.promptChunk(memory: memory, streaming: baseFacts?.streaming) {
            "Auto (\(chunk) on this Mac)"
        } else {
            "Auto (the engine decides by model size)"
        }
    }

    private var specAsSetUpLabel: String {
        if let window = baseFacts?.specWindow {
            "As set up (\(window))"
        } else {
            "As set up (none in the config; the engine's default is 2)"
        }
    }

    /// The offered values plus a saved one that is not among them, so that it stays selectable and visible.
    private func choices(_ values: [Int], including current: Int?) -> [Int] {
        guard let current, !values.contains(current) else { return values }
        return (values + [current]).sorted()
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
        library.update(root: draft.strataDirectoryURL)
        checkInstallation()
    }

    private func revert() {
        load(saved)
    }

    private func load(_ settings: StrataSettings) {
        draft = settings
        portText = String(settings.port)
    }

    private func checkInstallation() {
        if usesLibrary {
            library.refresh()
        }
        updateInstallationProblems()
    }

    private func updateInstallationProblems() {
        let installation = StrataInstallation(root: draft.strataDirectoryURL)
        installationProblems = usesLibrary ? library.launchProblems(for: draft.model) : installation.check(model: draft.model)
        baseFacts = installation.baseFacts(for: draft.model)
    }

    // MARK: - Deleting

    private func deletionBlocker(for status: ModelLibrary.PackStatus) -> String? {
        if installer.job == nil, installer.ownsProcess {
            return "a setup process started by this app may still be running"
        }
        return status.deletionBlocker(serverState: serverManager.state, job: installer.job)
    }

    private func files(for status: ModelLibrary.PackStatus) -> ModelFiles {
        let installation = StrataInstallation(root: library.root)
        if case .installed(let model) = status.state {
            return ModelFiles.forInstalled(model, installation: installation, data: library.dataDirectory, paths: paths)
        }
        return ModelFiles.forDownloaded(status.pack, installation: installation, data: library.dataDirectory)
    }

    private func confirmAndDelete(_ status: ModelLibrary.PackStatus) {
        let name = status.pack.name
        let confirmed = files(for: status)
        guard !confirmed.items.isEmpty else {
            library.refresh()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Move \(name) to the Trash?"
        alert.informativeText = confirmed.items.map { "• " + Self.abbreviated($0) }.joined(separator: "\n")
            + "\n\n\(ModelLibrary.PackStatus.gigabytes(confirmed.totalBytes)) GB in all, freed only once the Trash is emptied. "
            + "Strata's shared files and anything another installed model uses stay; the saved settings are not changed."
        let move = alert.addButton(withTitle: "Move to Trash")
        move.hasDestructiveAction = true
        move.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            // The server or a setup may have started on the model while the question was up.
            library.refresh()
            await library.checkExternalSetups()
            guard let current = library.packs.first(where: { $0.pack == status.pack }) else { return }
            if let blocker = deletionBlocker(for: current) {
                showDeletionProblem("\(name) was not moved to the Trash: \(blocker).")
                return
            }
            // Only what was listed in the question goes.
            let now = files(for: current)
            guard now.items == confirmed.items else {
                showDeletionProblem("What \(name) would move to the Trash changed while you were asked, so nothing was moved. Try again.")
                return
            }
            do {
                try now.trash()
            } catch {
                showDeletionProblem(error.localizedDescription)
            }
            library.refresh()
        }
    }

    private func showDeletionProblem(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The model was not deleted completely"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    // MARK: - Texts

    private var freeSpaceText: String {
        let free = library.freeBytes.map { "\(ModelLibrary.PackStatus.gigabytes($0)) GB free" } ?? "Free space unknown"
        return "\(free) in \(Self.abbreviated(library.dataDirectory.url)). Delete moves files to the Trash, which frees the space "
            + "only once it is emptied. Sizes are from Strata's docs; the disk estimate is for this Mac (\(memory.physicalMemoryGiB) GiB)."
    }

    private static func abbreviated(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }

    private static func describe(_ pack: ModelPack, memory: MemoryBudget) -> String {
        var parts = [pack.note, "download \(RunConfig.gigabytes(pack.downloadGB)) GB", "GPU maps \(RunConfig.gigabytes(pack.mappedFileGB)) GB"]
        if let needs = pack.needsAboutGB {
            parts.append("needs about \(RunConfig.gigabytes(needs)) GB")
        } else {
            parts.append("streams from the SSD")
        }
        parts.append("recommended from \(pack.recommendedFromGB) GB")
        parts.append("about \(RunConfig.gigabytes(pack.diskEstimateGB(memory: memory))) GB on disk")
        return parts.joined(separator: " · ")
    }
}
