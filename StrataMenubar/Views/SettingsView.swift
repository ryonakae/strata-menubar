import SwiftUI

struct SettingsView: View {
    let settingsStore: SettingsStore
    let serverManager: ServerManager

    @State private var draft: StrataSettings
    @State private var installationProblems: [String]?

    init(settingsStore: SettingsStore, serverManager: ServerManager) {
        self.settingsStore = settingsStore
        self.serverManager = serverManager
        _draft = State(initialValue: settingsStore.settings)
    }

    private var issues: [SettingsIssue] { draft.validate() }
    private var hasErrors: Bool { issues.contains { $0.severity == .error } }
    private var isDirty: Bool { draft != settingsStore.settings }
    private var running: RunningInfo? { serverManager.state.runningInfo }

    var body: some View {
        Form {
            Section("Strata installation") {
                TextField("Strata directory", text: $draft.strataDirectory)
                    .onSubmit(checkInstallation)
                HStack(alignment: .top) {
                    installationStatus
                    Spacer()
                    Button("Check") { checkInstallation() }
                }
                Text("The directory must contain Strata's `.venv`, `serve/server.py` and `strata-q2_0.json` from a finished setup. "
                    + "This app only runs the Q2_0 model and never installs, updates or edits anything there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Memory and context") {
                TextField("Expert cache (GB)", value: $draft.expertCacheGB, format: .number)
                TextField("Context (tokens)", value: $draft.maxContext, format: .number.grouping(.never))
                TextField("Port", value: $draft.port, format: .number.grouping(.never))
                ForEach(issues) { issue in
                    Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                        .font(.callout)
                }
                Text("The expert cache (STRATA_METAL_ARENA_GB) is only the arena for the most-used experts, not a limit on Strata's "
                    + "total memory: with a 5 GB cache the engine's footprint was about 10.6 GB. A fixed value is never shrunk "
                    + "automatically when memory runs short. \"About 16 GB overall\" is an operating goal, not a limit this app enforces.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Running server") {
                if let running {
                    LabeledContent("Started with", value: Self.describe(running.settings))
                    if running.settings != settingsStore.settings {
                        Text("The saved settings differ. They apply at the next start, or now with \"Save, Stop and Apply\".")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Not running. Saved settings apply at the next start.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button("Save") { save() }
                        .disabled(hasErrors || !isDirty)
                    if let running, running.settings != draft {
                        Button("Save, Stop and Apply") {
                            save()
                            let settings = draft
                            Task { await serverManager.restart(settings: settings) }
                        }
                        .disabled(hasErrors)
                    }
                    Spacer()
                    Button("Revert") { draft = settingsStore.settings }
                        .disabled(!isDirty)
                }
                Text("Pi reads this server at http://127.0.0.1:\(String(draft.port))/v1 with contextWindow 8192 in "
                    + "~/Dev/local/.pi/models.json. After changing the port or the context, edit that file by hand; this app never touches it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear(perform: checkInstallation)
    }

    @ViewBuilder
    private var installationStatus: some View {
        if let installationProblems {
            if installationProblems.isEmpty {
                Label("Installation looks complete", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(installationProblems, id: \.self) { problem in
                        Label(problem, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.callout)
            }
        } else {
            Text("Not checked yet")
                .foregroundStyle(.secondary)
        }
    }

    private func checkInstallation() {
        installationProblems = StrataInstallation(root: draft.strataDirectoryURL).check(model: draft.model)
    }

    private func save() {
        settingsStore.save(draft)
        checkInstallation()
    }

    private static func describe(_ settings: StrataSettings) -> String {
        "cache \(RunConfig.gigabytes(settings.expertCacheGB)) GB, context \(settings.maxContext), port \(settings.port)"
    }
}
