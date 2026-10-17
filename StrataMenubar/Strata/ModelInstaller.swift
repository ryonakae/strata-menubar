import Foundation
import Observation

enum SetupPurpose: Equatable, Sendable {
    case download
    /// The same run for a pack whose shards are complete: setup skips the download and only prepares it.
    case prepare
}

enum SetupPhase: Equatable, Sendable {
    /// Steps 1 to 4: the Mac, the choices, the Python packages and the engine, which setup rebuilds when it is stale.
    case checking(String)
    case downloading
    case preparing
    case writingConfig
}

struct DownloadProgress: Equatable, Sendable {
    var haveBytes: Int64
    var totalBytes: Int64

    var fraction: Double {
        totalBytes > 0 ? min(1, Double(haveBytes) / Double(totalBytes)) : 0
    }
}

struct InstallJob: Equatable, Sendable {
    let pack: ModelPack
    let purpose: SetupPurpose
    /// Setup's process, which leads the group every signal goes to.
    let pid: pid_t
    var phase: SetupPhase = .checking("starting setup")
    var progress: DownloadProgress?
    var cancelRequested = false
}

enum InstallOutcome: Equatable, Sendable {
    case installed(ModelPack)
    /// Every shard is on disk, but setup was stopped before preparing the pack because a server was running; the
    /// pack's first start prepares it.
    case downloaded(ModelPack)
    case cancelled(ModelPack)
    case failed(ModelPack, String)
}

enum InstallError: Error, Equatable, LocalizedError {
    case busy
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .busy: "Another setup is already running."
        case .cancelled: "The setup was stopped."
        case .failed(let message): message
        }
    }
}

/// Runs Strata's own setup as a process this app owns, to download a pack or to prepare a downloaded one, and
/// follows its log for the progress. One run at a time; what it leaves on disk decides the outcome, not its exit
/// status, because setup's own refusals and this app's interrupt both end in an exit of 1.
@MainActor
@Observable
final class ModelInstaller {
    struct Timing: Sendable {
        var logPollInterval: Duration = .milliseconds(500)
        /// Setup answers SIGINT by closing its files and printing "stopped."; after that the server's steps follow.
        var interruptTimeout: Duration = .seconds(20)
        var terminateTimeout: Duration = .seconds(20)
        var killTimeout: Duration = .seconds(10)
        var pollInterval: Duration = .milliseconds(100)

        static let standard = Timing()
    }

    private(set) var job: InstallJob?
    /// The last run's result, shown until the next run starts.
    private(set) var lastOutcome: InstallOutcome?
    /// Whether a server is up, which setup's preparation must not run beside; the app wires this to the server
    /// manager. Until it does, everything counts as running, which at worst stops a download before preparing.
    var serverIsRunning: @MainActor () -> Bool = { true }

    private let launcher: any ProcessLaunching
    private let paths: AppPaths
    private let library: ModelLibrary
    private let timing: Timing
    @ObservationIgnored private var process: (any OwnedProcess)?

    init(launcher: any ProcessLaunching, paths: AppPaths, library: ModelLibrary, timing: Timing = .standard) {
        self.launcher = launcher
        self.paths = paths
        self.library = library
        self.timing = timing
    }

    /// Whether a process group started here has not yet been confirmed gone.
    var ownsProcess: Bool { process != nil }
    var processGroup: pid_t? { process?.processGroup }

    var quitDescription: String? {
        guard let job else {
            return process.map { "A setup process started by this app (process group \($0.processGroup)) may still be running" }
        }
        return switch job.purpose {
        case .download: "A download of \(job.pack.name) (PID \(job.pid)) is running"
        case .prepare: "The preparation of \(job.pack.name) (PID \(job.pid)) is running"
        }
    }

    /// One line for the menu and the settings window: what the run is doing, or how the last one ended.
    var statusLine: String? {
        if let job {
            let name = job.pack.name
            if job.cancelRequested {
                return "Stopping \(job.purpose == .download ? "the download" : "the preparation") of \(name)…"
            }
            switch job.phase {
            case .checking(let title):
                return "\(name): \(title)…"
            case .downloading:
                guard let progress = job.progress else { return "Downloading \(name)…" }
                return "Downloading \(name): \(Int(progress.fraction * 100))% (\(Self.gigabytes(progress.haveBytes)) / \(Self.gigabytes(progress.totalBytes)) GB)"
            case .preparing:
                return "Preparing \(name)…"
            case .writingConfig:
                return "Finishing \(name)…"
            }
        }
        switch lastOutcome {
        case .installed(let pack):
            return "\(pack.name) installed"
        case .downloaded(let pack):
            return "\(pack.name) downloaded; it is prepared at its first start"
        case .cancelled(let pack):
            return "Setup of \(pack.name) stopped; the next Download or start resumes it"
        case .failed(let pack, let message):
            return "\(pack.name) failed: \(message)\(message.hasSuffix(".") ? "" : ".") See the setup log."
        case nil:
            return nil
        }
    }

    /// Downloads the pack with setup, or resumes it. Nothing happens for an installed pack, one another setup is
    /// working on, or while a run is in progress: the window disables the button first, this is the last guard.
    func download(_ pack: ModelPack) async {
        guard process == nil else { return }
        // A setup started in a terminal since the last look must not be joined.
        library.refresh()
        await library.checkExternalSetups()
        guard process == nil, let status = library.packs.first(where: { $0.pack == pack }), !status.busyElsewhere else { return }
        if case .installed = status.state { return }
        _ = await run(pack, purpose: .download)
    }

    /// Prepares a downloaded pack with the same setup run; the caller makes sure no server is running.
    func prepare(_ pack: ModelPack) async throws {
        guard process == nil else { throw InstallError.busy }
        switch await run(pack, purpose: .prepare) {
        case .installed:
            return
        case .cancelled:
            throw InstallError.cancelled
        case .downloaded(let pack):
            throw InstallError.failed("Setup ended without writing strata-\(pack.tag).json.")
        case .failed(_, let message):
            throw InstallError.failed(message)
        }
    }

    /// Stops the run: SIGINT, which setup takes as a clean stop, then the server's SIGTERM and SIGKILL steps.
    /// What is on disk stays, and the next run of the same pack continues from it.
    func cancel() async {
        guard let process else { return }
        job?.cancelRequested = true
        let gone = await endGroup(process, interrupt: true)
        if job != nil {
            // The run reports the outcome once it has read the rest of the log.
            _ = await poll(within: timing.killTimeout) { job == nil }
        } else if gone {
            self.process = nil
        }
    }

    // MARK: - The run

    private func run(_ pack: ModelPack, purpose: SetupPurpose) async -> InstallOutcome {
        lastOutcome = nil
        let log = paths.setupLog
        do {
            try LogStore(paths: paths).prepareForSetup()
        } catch {
            return finish(.failed(pack, "The setup log could not be prepared: \(error.localizedDescription)"))
        }
        // Everything already in the log belongs to an earlier run.
        var tail = LogTail(url: log)
        let plan = SetupPlan.make(installation: StrataInstallation(root: library.root), pack: pack, log: log)
        let process: any OwnedProcess
        do {
            process = try launcher.launch(plan)
        } catch {
            return finish(.failed(pack, "Setup could not be started: \(error.localizedDescription)"))
        }
        self.process = process
        job = InstallJob(pack: pack, purpose: purpose, pid: process.pid)

        var lastFailure: String?
        let exit = await follow(process, tail: &tail) { event in
            handle(event, process: process, lastFailure: &lastFailure)
        }
        let clean = await endGroup(process, interrupt: false)
        library.refresh()
        let state = library.packs.first { $0.pack == pack }?.state

        let outcome: InstallOutcome
        if !clean {
            outcome = .failed(pack, "Setup's process group \(process.processGroup) is still alive. Check Activity Monitor, then try again.")
        } else if case .installed = state {
            outcome = .installed(pack)
        } else if purpose == .download, state == .downloaded {
            outcome = .downloaded(pack)
        } else if job?.cancelRequested == true {
            outcome = .cancelled(pack)
        } else {
            outcome = .failed(pack, lastFailure ?? "Setup ended with \(exit) before finishing.")
        }
        if clean {
            self.process = nil
        }
        return finish(outcome)
    }

    private func finish(_ outcome: InstallOutcome) -> InstallOutcome {
        job = nil
        lastOutcome = outcome
        return outcome
    }

    /// Reads the log until the direct child has exited and the rest of its output is in. The exit is checked before
    /// each read, so the read after it has everything setup wrote.
    private func follow(_ process: any OwnedProcess, tail: inout LogTail, onEvent: (SetupEvent) -> Void) async -> ProcessExit {
        var parser = SetupOutputParser()
        while true {
            let exit = process.exitIfFinished()
            var events = parser.feed(tail.readNew())
            if exit != nil {
                events += parser.finish()
            }
            events.forEach(onEvent)
            if let exit {
                return exit
            }
            try? await Task.sleep(for: timing.logPollInterval)
        }
    }

    private func handle(_ event: SetupEvent, process: any OwnedProcess, lastFailure: inout String?) {
        guard var current = job else { return }
        switch event {
        case .step(let number, let title):
            switch number {
            case ...4:
                current.phase = .checking(title)
            case 5:
                current.phase = .downloading
            case 6:
                current.phase = .preparing
                // Preparing moves well over 100 GB on disk and must not run beside a loaded engine (a Mac froze twice
                // doing that). Setup's own guard only looks for a live engine process, which misses one that idle
                // unload has paused and a server whose stop failed; so a download stops here and the first start prepares.
                if current.purpose == .download, serverIsRunning() {
                    try? process.signalGroup(SIGINT)
                }
            default:
                current.phase = .writingConfig
            }
        case .shardProgress(let name, let have, _):
            current.progress = DownloadProgress(
                haveBytes: finishedShardBytes(of: current.pack, except: name) + have,
                totalBytes: Int64((current.pack.downloadGB * 1e9).rounded())
            )
        case .failure(let message):
            lastFailure = message
        case .alreadyDownloaded, .stopped:
            break
        }
        job = current
    }

    /// The shards setup has finished and marked, by their size on disk; a progress line only covers the current one.
    private func finishedShardBytes(of pack: ModelPack, except current: String) -> Int64 {
        let directory = library.dataDirectory.modelDirectory(for: pack)
        let fm = FileManager.default
        return pack.shardNames.filter { $0 != current }.reduce(Int64(0)) { sum, name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            guard fm.fileExists(atPath: path + ".done") else { return sum }
            let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber
            return sum + (size?.int64Value ?? 0)
        }
    }

    // MARK: - Ending the group

    /// True once the group is empty. SIGINT comes first only for a stop the user or the server guard asked for; a
    /// group that outlives its leader's own exit gets the server's SIGTERM and SIGKILL steps right away.
    private func endGroup(_ process: any OwnedProcess, interrupt: Bool) async -> Bool {
        if await groupGone(process, within: .zero) {
            return true
        }
        if interrupt {
            try? process.signalGroup(SIGINT)
            if await groupGone(process, within: timing.interruptTimeout) {
                return true
            }
        }
        try? process.signalGroup(SIGTERM)
        if await groupGone(process, within: timing.terminateTimeout) {
            return true
        }
        try? process.signalGroup(SIGKILL)
        return await groupGone(process, within: timing.killTimeout)
    }

    private func groupGone(_ process: any OwnedProcess, within timeout: Duration) async -> Bool {
        await poll(within: timeout) { !process.isGroupAlive() }
    }

    private func poll(within timeout: Duration, until condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            if condition() {
                return true
            }
            if clock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: timing.pollInterval)
        }
    }

    private static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1e9)
    }
}

extension ModelInstaller: ModelPreparing {
    /// From setup's step 6 on: the download was not interrupted there, so it prepares the pack itself.
    var isPreparing: Bool {
        job?.phase == .preparing || job?.phase == .writingConfig
    }

    /// A pack whose shards are complete and marked but which has no config yet.
    func needsPreparation(model tag: String) -> Bool {
        library.refresh()
        return library.downloadedPack(forTag: tag) != nil
    }

    func prepare(model tag: String) async throws {
        guard let pack = library.downloadedPack(forTag: tag) else {
            throw InstallError.failed("\(tag) is not a downloaded pack.")
        }
        try await prepare(pack)
    }

    func cancelPreparation() async {
        await cancel()
    }
}

/// What setup appended to its log since the last read, starting after whatever the file held before the run.
struct LogTail {
    let url: URL
    private var offset: UInt64

    init(url: URL) {
        self.url = url
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? NSNumber
        offset = size?.uint64Value ?? 0
    }

    mutating func readNew() -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd(), !data.isEmpty else { return "" }
        offset += UInt64(data.count)
        return String(decoding: data, as: UTF8.self)
    }
}
