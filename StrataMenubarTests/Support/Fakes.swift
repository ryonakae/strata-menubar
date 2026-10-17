import Foundation
@testable import StrataMenubar

/// A process whose reaction to signals the test chooses. Signals are recorded in the order the manager sends them.
final class FakeProcess: OwnedProcess, @unchecked Sendable {
    enum Target: Equatable {
        case process
        case group
    }

    struct Behavior: Sendable {
        var exitsOnProcessSignal: Set<Int32> = [SIGTERM, SIGKILL]
        var exitsOnGroupSignal: Set<Int32> = [SIGTERM, SIGKILL]
        /// Models the engine outliving the server: the group stays alive after the process exits until a group signal in `groupDiesOnSignal`.
        var groupSurvivesProcessExit = false
        var groupDiesOnSignal: Set<Int32> = [SIGTERM, SIGKILL]

        static let cooperative = Behavior()
        static let immortal = Behavior(exitsOnProcessSignal: [], exitsOnGroupSignal: [], groupSurvivesProcessExit: true, groupDiesOnSignal: [])
    }

    let pid: pid_t
    var processGroup: pid_t { pid }
    let behavior: Behavior

    private let lock = NSLock()
    private var exitResult: ProcessExit?
    private var groupAlive = true
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []
    private var recorded: [(Target, Int32)] = []

    init(pid: pid_t, behavior: Behavior) {
        self.pid = pid
        self.behavior = behavior
    }

    var signals: [(target: Target, signal: Int32)] {
        lock.withLock { recorded.map { (target: $0.0, signal: $0.1) } }
    }

    var hasExited: Bool {
        lock.withLock { exitResult != nil }
    }

    func exitIfFinished() -> ProcessExit? {
        lock.withLock { exitResult }
    }

    func exit(with result: ProcessExit) {
        finish(result)
    }

    func waitForExit() async -> ProcessExit {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let exitResult {
                lock.unlock()
                continuation.resume(returning: exitResult)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func signal(_ signal: Int32) throws {
        lock.withLock { recorded.append((.process, signal)) }
        if behavior.exitsOnProcessSignal.contains(signal) {
            finish(.signaled(signal))
        }
    }

    func signalGroup(_ signal: Int32) throws {
        lock.withLock { recorded.append((.group, signal)) }
        if behavior.exitsOnGroupSignal.contains(signal) {
            finish(.signaled(signal))
        }
        if behavior.groupDiesOnSignal.contains(signal) {
            lock.withLock { groupAlive = false }
        }
    }

    func isGroupAlive() -> Bool {
        lock.withLock { exitResult == nil || groupAlive }
    }

    private func finish(_ result: ProcessExit) {
        lock.lock()
        guard exitResult == nil else {
            lock.unlock()
            return
        }
        exitResult = result
        if !behavior.groupSurvivesProcessExit {
            groupAlive = false
        }
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume(returning: result) }
    }
}

final class FakeLauncher: ProcessLaunching, @unchecked Sendable {
    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "spawn refused by the test" }
    }

    private let lock = NSLock()
    private var launched: [FakeProcess] = []
    private var received: [LaunchPlan] = []
    var nextBehavior: FakeProcess.Behavior = .cooperative
    var failsToLaunch = false

    var processes: [FakeProcess] { lock.withLock { launched } }
    var plans: [LaunchPlan] { lock.withLock { received } }

    func launch(_ plan: LaunchPlan) throws -> any OwnedProcess {
        if failsToLaunch {
            throw Failure()
        }
        return lock.withLock {
            received.append(plan)
            let process = FakeProcess(pid: pid_t(1000 + launched.count), behavior: nextBehavior)
            launched.append(process)
            return process
        }
    }
}

final class FakePlanner: LaunchPlanning, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [StrataSettings] = []
    var error: LaunchPlanError?

    var received: [StrataSettings] { lock.withLock { seen } }

    static func plan(for settings: StrataSettings) -> LaunchPlan {
        LaunchPlan(
            executable: URL(filePath: "/fake/python"),
            arguments: ["server.py", "--port", String(settings.port)],
            workingDirectory: URL(filePath: "/fake"),
            environment: [:],
            standardOutputLog: URL(filePath: "/fake/server.log")
        )
    }

    func makePlan(settings: StrataSettings) throws -> LaunchPlan {
        lock.withLock { seen.append(settings) }
        if let error {
            throw error
        }
        return Self.plan(for: settings)
    }
}

/// Answers probes from a script (the last entry repeats), or, in manual mode, only when the test resolves them in order.
final class FakeProbe: HealthProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [HealthProbeResult]
    private var pending: [CheckedContinuation<HealthProbeResult, Never>] = []
    private var count = 0
    let manual: Bool

    init(script: [HealthProbeResult] = [.unreachable], manual: Bool = false) {
        self.script = script
        self.manual = manual
    }

    var calls: Int { lock.withLock { count } }

    func setScript(_ newScript: [HealthProbeResult]) {
        lock.withLock { script = newScript }
    }

    func probe(port: Int) async -> HealthProbeResult {
        let scripted: HealthProbeResult? = lock.withLock {
            count += 1
            if manual {
                return nil
            }
            return script.count > 1 ? script.removeFirst() : script[0]
        }
        if let scripted {
            return scripted
        }
        return await withCheckedContinuation { continuation in
            lock.withLock { pending.append(continuation) }
        }
    }

    /// Answers the oldest unanswered probe, waiting for one to arrive first.
    func resolveNext(_ result: HealthProbeResult) async {
        await resolve(result, at: 0)
    }

    /// Answers the probe at `index` among the unanswered ones (oldest first), waiting until that many are pending.
    func resolve(_ result: HealthProbeResult, at index: Int) async {
        while true {
            let next: CheckedContinuation<HealthProbeResult, Never>? = lock.withLock {
                pending.count > index ? pending.remove(at: index) : nil
            }
            if let next {
                next.resume(returning: result)
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}

extension StrataHealth {
    static func loaded(model: String = "qwen3.8-flash-next-q2_0", maxContext: Int = 8192) -> StrataHealth {
        StrataHealth(loaded: true, model: model, maxContext: maxContext)
    }

    static let loading = StrataHealth(loaded: false, model: "qwen3.8-flash-next-q2_0", maxContext: 0)
}

extension ServerManager.Timing {
    static let fast = ServerManager.Timing(
        healthPollInterval: .milliseconds(5),
        startupDeadline: .milliseconds(200),
        serverExitTimeout: .milliseconds(200),
        groupTerminateTimeout: .milliseconds(100),
        groupKillTimeout: .milliseconds(100),
        groupPollInterval: .milliseconds(5),
        monitorInterval: .milliseconds(20)
    )
}

/// Stands in for the installer: which models need preparing, and how each preparation ends, is the test's choice.
@MainActor
final class FakePreparer: ModelPreparing {
    var needs: Set<String> = []
    var isPreparing = false
    /// When set, a preparation ends with this at once; otherwise it waits for `finish()`, `fail(_:)` or a cancel.
    var immediate: Result<Void, any Error>?
    private(set) var prepared: [String] = []
    private(set) var cancelled = 0
    private var pending: CheckedContinuation<Void, any Error>?

    func needsPreparation(model tag: String) -> Bool {
        needs.contains(tag)
    }

    func prepare(model tag: String) async throws {
        prepared.append(tag)
        if let immediate {
            return try immediate.get()
        }
        try await withCheckedThrowingContinuation { pending = $0 }
    }

    func cancelPreparation() async {
        cancelled += 1
        resolve(.failure(InstallError.cancelled))
    }

    func finish() {
        resolve(.success(()))
    }

    func fail(_ message: String) {
        resolve(.failure(InstallError.failed(message)))
    }

    private func resolve(_ result: Result<Void, any Error>) {
        guard let pending else { return }
        self.pending = nil
        pending.resume(with: result)
    }
}

extension ModelInstaller.Timing {
    static let fast = ModelInstaller.Timing(
        logPollInterval: .milliseconds(10),
        interruptTimeout: .milliseconds(50),
        terminateTimeout: .milliseconds(50),
        killTimeout: .milliseconds(200),
        pollInterval: .milliseconds(5)
    )
}

/// Polls a main-actor condition instead of sleeping for a fixed time.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline {
            return false
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

extension ServerState {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
