import Foundation
import Observation

/// What is installed, downloaded or still arriving for every pack of the catalog, kept current by watching the
/// Strata directory and the data directory. Views read this instead of listing the directories themselves, so that a
/// model set up from a terminal or removed in the Finder shows up without restarting the app.
@MainActor
@Observable
final class ModelLibrary {
    struct PackStatus: Identifiable, Equatable {
        enum State: Equatable {
            case installed(InstalledModel)
            /// Every shard is on disk with its mark, but no config yet: the first start prepares it.
            case downloaded
            case partial(bytes: Int64)
            case notDownloaded
        }

        let pack: ModelPack
        var state: State
        /// A setup this app did not start is working on the pack: nothing here may touch it.
        var busyElsewhere = false

        var id: String { pack.name }
    }

    /// An entry of the settings window's model picker.
    enum ModelChoice: Identifiable, Equatable {
        case installed(InstalledModel)
        /// Every shard is on disk but the first start still has to prepare it.
        case downloaded(ModelPack)
        /// The selected model is neither installed nor downloaded; it stays listed so the selection remains visible.
        case unknown(tag: String)

        var tag: String {
            switch self {
            case .installed(let model): model.tag
            case .downloaded(let pack): pack.tag
            case .unknown(let tag): tag
            }
        }

        var id: String { tag }
    }

    /// The picker follows the pack rows so a model keeps its place whether it is downloaded or installed; configs
    /// that no pack produced follow by tag.
    static func choices(installed: [InstalledModel], packs: [PackStatus], selected: String) -> [ModelChoice] {
        var choices: [ModelChoice] = packs.compactMap { status in
            switch status.state {
            case .installed(let model): .installed(model)
            case .downloaded: .downloaded(status.pack)
            case .partial, .notDownloaded: nil
            }
        }
        let packTags = Set(packs.map(\.pack.tag))
        choices += installed.filter { !packTags.contains($0.tag) }.sorted { $0.tag < $1.tag }.map { .installed($0) }
        if !choices.contains(where: { $0.tag == selected }) {
            choices.append(.unknown(tag: selected))
        }
        return choices
    }

    private(set) var root: URL
    private(set) var dataDirectory: StrataDataDirectory
    private(set) var installed: [InstalledModel] = []
    private(set) var packs: [PackStatus] = []
    private(set) var freeBytes: Int64?
    /// The process group of the setup this app runs, so that it is not mistaken for somebody else's.
    var ownedSetupGroup: @MainActor () -> pid_t? = { nil }

    private let settingsFile: URL
    private let watching: Bool
    private let externalSetups: (pid_t?) async -> [ExternalSetup]
    @ObservationIgnored private var watchers: [String: DirectoryWatcher] = [:]
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var externalScan: Task<Void, Never>?

    /// `externalSetups` reads the process table; tests that must not see the host's processes hand in their own.
    init(
        root: URL,
        settingsFile: URL = StrataDataDirectory.defaultSettingsFile,
        watching: Bool = true,
        externalSetups: @escaping (pid_t?) async -> [ExternalSetup] = ExternalSetup.running(excludingGroup:)
    ) {
        self.root = root
        self.settingsFile = settingsFile
        self.watching = watching
        self.externalSetups = externalSetups
        dataDirectory = StrataDataDirectory.resolve(strataRoot: root, settingsFile: settingsFile)
        refresh()
    }

    func update(root: URL) {
        guard root.path(percentEncoded: false) != self.root.path(percentEncoded: false) else { return }
        self.root = root
        refresh()
    }

    /// Reads the directories now; the process table, which says what another setup is working on, follows in the
    /// background and the last reading stands until it is in.
    func refresh() {
        dataDirectory = StrataDataDirectory.resolve(strataRoot: root, settingsFile: settingsFile)
        let scan = Self.scan(root: root, dataDirectory: dataDirectory)
        installed = scan.installed
        let previous = packs
        packs = scan.packs.map { status in
            var status = status
            status.busyElsewhere = previous.first { $0.pack == status.pack }?.busyElsewhere ?? false
            return status
        }
        freeBytes = dataDirectory.freeBytes()
        if watching {
            rearmWatchers()
        }
        externalScan?.cancel()
        externalScan = Task { @MainActor [weak self] in
            guard let self else { return }
            let external = await externalSetups(ownedSetupGroup())
            guard !Task.isCancelled else { return }
            mark(external)
        }
    }

    /// Looks for a setup outside the app right now, for a guard that must not act on the last reading. A reading
    /// still under way in the background is dropped, so that it cannot land after this one.
    func checkExternalSetups() async {
        externalScan?.cancel()
        externalScan = nil
        mark(await externalSetups(ownedSetupGroup()))
    }

    private func mark(_ external: [ExternalSetup]) {
        packs = packs.map { status in
            var status = status
            status.busyElsewhere = external.contains { $0.worksOn(status.pack) }
            return status
        }
    }

    /// The pack behind a tag whose download is complete but which has no config yet.
    func downloadedPack(forTag tag: String) -> ModelPack? {
        packs.first { $0.pack.tag == tag && $0.state == .downloaded }?.pack
    }

    /// What a launch of the model would trip over. A downloaded model has no config yet, which is not a problem:
    /// its first start prepares it, for which the checkout's interpreter and server still have to be there.
    func launchProblems(for tag: String) -> [String] {
        let installation = StrataInstallation(root: root)
        if downloadedPack(forTag: tag) != nil {
            return installation.checkRuntime()
        }
        return installation.check(model: tag)
    }

    /// One reading of the directories without watching them, for a directory the user is typing but has not saved.
    static func scan(root: URL, dataDirectory: StrataDataDirectory? = nil) -> (installed: [InstalledModel], packs: [PackStatus]) {
        let data = dataDirectory ?? StrataDataDirectory.resolve(strataRoot: root)
        let installed = StrataInstallation(root: root).installedModels()
        let packs = StrataModelCatalog.packs.map { pack -> PackStatus in
            if let model = installed.first(where: { $0.tag == pack.tag }) {
                return PackStatus(pack: pack, state: .installed(model))
            }
            return switch data.packState(for: pack) {
            case .downloaded: PackStatus(pack: pack, state: .downloaded)
            case .partial(let bytes): PackStatus(pack: pack, state: .partial(bytes: bytes))
            case .notDownloaded: PackStatus(pack: pack, state: .notDownloaded)
            }
        }
        return (installed, packs)
    }

    // MARK: - Watching

    var watchedPaths: Set<String> { Set(watchers.keys) }

    /// A vnode source only reports the directory's own entries, so each model directory gets a source of its own
    /// once it exists; the data directory and `models/` report new directories, after which the next pass arms them.
    /// A directory deleted and created again is a new vnode, so its stale source is dropped and the path armed anew.
    private func rearmWatchers() {
        let wanted = [root, dataDirectory.url, dataDirectory.models] + packs.map { dataDirectory.modelDirectory(for: $0.pack) }
        let paths = Set(wanted.map { $0.path(percentEncoded: false) })
        watchers = watchers.filter { paths.contains($0.key) && !$0.value.isStale }
        for path in paths where watchers[path] == nil {
            watchers[path] = DirectoryWatcher(path: path) { [weak self] in
                Task { @MainActor in
                    self?.scheduleRefresh()
                }
            }
        }
    }

    /// Setup writes files in bursts; one refresh after the burst is enough.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
