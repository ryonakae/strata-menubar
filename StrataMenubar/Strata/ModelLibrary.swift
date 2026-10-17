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

    private(set) var root: URL
    private(set) var dataDirectory: StrataDataDirectory
    private(set) var installed: [InstalledModel] = []
    private(set) var packs: [PackStatus] = []
    private(set) var freeBytes: Int64?
    /// The process group of the setup this app runs, so that it is not mistaken for somebody else's.
    var ownedSetupGroup: @MainActor () -> pid_t? = { nil }

    private let settingsFile: URL
    private let watching: Bool
    @ObservationIgnored private var watchers: [String: DirectoryWatcher] = [:]
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    init(root: URL, settingsFile: URL = StrataDataDirectory.defaultSettingsFile, watching: Bool = true) {
        self.root = root
        self.settingsFile = settingsFile
        self.watching = watching
        dataDirectory = StrataDataDirectory.resolve(strataRoot: root, settingsFile: settingsFile)
        refresh()
    }

    func update(root: URL) {
        guard root.path(percentEncoded: false) != self.root.path(percentEncoded: false) else { return }
        self.root = root
        refresh()
    }

    func refresh() {
        dataDirectory = StrataDataDirectory.resolve(strataRoot: root, settingsFile: settingsFile)
        let scan = Self.scan(root: root, dataDirectory: dataDirectory)
        installed = scan.installed
        let external = ExternalSetup.running(excludingGroup: ownedSetupGroup())
        packs = scan.packs.map { status in
            var status = status
            status.busyElsewhere = external.contains { $0.model == nil || $0.model == status.pack.name }
            return status
        }
        freeBytes = dataDirectory.freeBytes()
        if watching {
            rearmWatchers()
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

    /// A vnode source only reports the directory's own entries, so each model directory gets a source of its own
    /// once it exists; the data directory and `models/` report new directories, after which the next pass arms them.
    private func rearmWatchers() {
        let wanted = [root, dataDirectory.url, dataDirectory.models] + packs.map { dataDirectory.modelDirectory(for: $0.pack) }
        let paths = Set(wanted.map { $0.path(percentEncoded: false) })
        watchers = watchers.filter { paths.contains($0.key) }
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
