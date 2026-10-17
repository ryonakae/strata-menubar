import Foundation
import Observation

/// Prepares a downloaded model before its first start; the installer does it with Strata's setup.
@MainActor
protocol ModelPreparing: AnyObject {
    /// Setup is preparing a model on a run of its own, which moves well over 100 GB on disk: no engine may load beside it.
    var isPreparing: Bool { get }
    func needsPreparation(model tag: String) -> Bool
    func prepare(model tag: String) async throws
    func cancelPreparation() async
}

/// For a manager without an installer: every model counts as ready.
@MainActor
final class NoPreparation: ModelPreparing {
    var isPreparing: Bool { false }
    func needsPreparation(model tag: String) -> Bool { false }
    func prepare(model tag: String) async throws {}
    func cancelPreparation() async {}
}

/// Owns the Strata server process this app starts and publishes its state to the UI.
///
/// Every start, stop and restart runs through one serial queue, so repeated clicks cannot spawn a second process,
/// and every owned process carries a generation so that a late health answer or exit notification from an earlier
/// launch cannot touch a later one.
@MainActor
@Observable
final class ServerManager {
    struct Timing: Sendable {
        var healthPollInterval: Duration = .seconds(1)
        var startupDeadline: Duration = .seconds(600)
        /// How long a running server gets after SIGTERM to close its engine itself (the server tries QUIT, terminate
        /// and kill with 20 s each).
        var serverExitTimeout: Duration = .seconds(90)
        var groupTerminateTimeout: Duration = .seconds(20)
        var groupKillTimeout: Duration = .seconds(10)
        var groupPollInterval: Duration = .milliseconds(100)
        var monitorInterval: Duration = .seconds(10)

        static let standard = Timing()
    }

    private enum StopReason {
        case requested
        case startupTimeout
        case unexpectedExit(ProcessExit)
    }

    private struct OwnedServer {
        let process: any OwnedProcess
        let generation: Int
        let settings: StrataSettings
    }

    private(set) var state: ServerState = .stopped

    private let launcher: any ProcessLaunching
    private let probe: any HealthProbing
    private let planner: any LaunchPlanning
    private let preparer: any ModelPreparing
    private let timing: Timing

    private var owned: OwnedServer?
    private var generation = 0
    private var operation: Task<Void, Never>?
    private var operationID = 0
    private var readiness: Task<Void, Never>?
    private var monitor: Task<Void, Never>?

    init(
        launcher: any ProcessLaunching,
        probe: any HealthProbing,
        planner: any LaunchPlanning,
        preparer: any ModelPreparing = NoPreparation(),
        timing: Timing = .standard
    ) {
        self.launcher = launcher
        self.probe = probe
        self.planner = planner
        self.preparer = preparer
        self.timing = timing
    }

    /// Whether a process group started by this app has not yet been confirmed gone.
    var ownsProcess: Bool { owned != nil }

    var quitRequirement: QuitRequirement {
        QuitRequirement(state: state, ownsProcess: ownsProcess)
    }

    var canStart: Bool {
        guard owned == nil, !preparer.isPreparing else { return false }
        switch state {
        case .stopped, .failed: return true
        case .starting, .running, .stopping, .external: return false
        }
    }

    /// While a model is being prepared nothing is owned yet, but the preparation can be stopped.
    var canStop: Bool {
        switch state {
        case .starting: return true
        case .running, .failed: return owned != nil
        case .stopped, .stopping, .external: return false
        }
    }

    func start(settings: StrataSettings) async {
        await enqueue { [self] in
            guard canStart else { return }
            await performStart(settings)
        }
    }

    func stop() async {
        // A preparation waits inside the start's own operation, so its cancel cannot go through the queue.
        if case .starting(let info) = state, info.phase == .preparing {
            await preparer.cancelPreparation()
        }
        await enqueue { [self] in
            guard canStop else { return }
            await stopOwned(reason: .requested)
        }
    }

    func restart(settings: StrataSettings) async {
        await enqueue { [self] in
            if canStop {
                await stopOwned(reason: .requested)
            }
            guard canStart else { return }
            await performStart(settings)
        }
    }

    /// Looks at the port while nothing is owned, to show or clear an externally started server.
    func refresh(port: Int) async {
        guard isIdleWithoutProcess else { return }
        let result = await probe.probe(port: port)
        guard isIdleWithoutProcess else { return }
        switch (result, state) {
        case (.strata(let health), _):
            state = .external(ExternalInfo(port: port, loaded: health.loaded, model: health.model, maxContext: health.maxContext))
        case (_, .external):
            state = .stopped
        default:
            break
        }
    }

    func startMonitoring(port: @escaping @MainActor () -> Int) {
        guard monitor == nil else { return }
        let interval = timing.monitorInterval
        monitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                await monitorTick(port: port())
            }
        }
    }

    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    /// Returns once no start, stop or cleanup is in flight.
    func waitForIdle() async {
        while let operation {
            await operation.value
        }
    }

    // MARK: - Serialisation

    private func enqueue(_ body: @escaping @MainActor () async -> Void) async {
        let previous = operation
        operationID += 1
        let id = operationID
        let task = Task { @MainActor [self] in
            await previous?.value
            await body()
            // Cleared from inside the task: once `value` returns, the queue really is empty or has moved on, so
            // `waitForIdle` never spins on a finished task whose owner has not run yet.
            if operationID == id {
                operation = nil
            }
        }
        operation = task
        await task.value
    }

    private var isIdleWithoutProcess: Bool {
        guard owned == nil, operation == nil else { return false }
        switch state {
        case .stopped, .external, .failed: return true
        case .starting, .running, .stopping: return false
        }
    }

    private func isCurrent(_ server: OwnedServer) -> Bool {
        owned?.generation == server.generation
    }

    // MARK: - Starting

    private func performStart(_ settings: StrataSettings) async {
        switch await probe.probe(port: settings.port) {
        case .strata(let health):
            state = .external(ExternalInfo(port: settings.port, loaded: health.loaded, model: health.model, maxContext: health.maxContext))
            return
        case .occupied(let detail):
            state = .failed("Port \(settings.port) is in use by something that is not Strata: \(detail)")
            return
        case .unreachable:
            break
        }
        if preparer.needsPreparation(model: settings.model) {
            state = .starting(StartingInfo(model: settings.model, phase: .preparing, port: settings.port, since: Date()))
            do {
                try await preparer.prepare(model: settings.model)
            } catch InstallError.cancelled {
                state = .stopped
                return
            } catch {
                let message = error.localizedDescription
                state = .failed("The model could not be prepared: \(message)\(message.hasSuffix(".") ? "" : ".") See the setup log.")
                return
            }
        }
        let plan: LaunchPlan
        do {
            plan = try planner.makePlan(settings: settings)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        let process: any OwnedProcess
        do {
            process = try launcher.launch(plan)
        } catch {
            state = .failed("The server could not be started: \(error.localizedDescription)")
            return
        }
        generation += 1
        let server = OwnedServer(process: process, generation: generation, settings: settings)
        owned = server
        state = .starting(StartingInfo(model: settings.model, phase: .loading(pid: process.pid), port: settings.port, since: Date()))
        watchExit(of: server)
        readiness = Task { @MainActor [self] in
            await awaitReadiness(of: server)
        }
    }

    private func awaitReadiness(of server: OwnedServer) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timing.startupDeadline
        while !Task.isCancelled {
            let result = await probe.probe(port: server.settings.port)
            guard !Task.isCancelled, isCurrent(server), case .starting = state else { return }
            if case .strata(let health) = result, health.loaded {
                state = .running(RunningInfo(
                    pid: server.process.pid,
                    settings: server.settings,
                    model: health.model,
                    maxContext: health.maxContext,
                    since: Date(),
                    health: .ok
                ))
                return
            }
            if clock.now >= deadline {
                // The cleanup must not run inside this task: stopping cancels it, which would cut the waits short.
                Task { @MainActor [self] in
                    await enqueue {
                        guard self.isCurrent(server), case .starting = self.state else { return }
                        await self.stopOwned(reason: .startupTimeout)
                    }
                }
                return
            }
            try? await Task.sleep(for: timing.healthPollInterval)
        }
    }

    private func watchExit(of server: OwnedServer) {
        Task { @MainActor [self] in
            let exit = await server.process.waitForExit()
            await enqueue {
                guard self.isCurrent(server) else { return }
                switch self.state {
                case .starting, .running:
                    await self.stopOwned(reason: .unexpectedExit(exit))
                case .stopped, .stopping, .external, .failed:
                    return
                }
            }
        }
    }

    private func monitorTick(port: Int) async {
        if case .running(let info) = state, let server = owned {
            let result = await probe.probe(port: info.port)
            guard isCurrent(server), case .running(var current) = state else { return }
            current.health = HealthStatus(result)
            state = .running(current)
        } else {
            await refresh(port: port)
        }
    }

    // MARK: - Stopping

    private func stopOwned(reason: StopReason) async {
        guard let server = owned else { return }
        readiness?.cancel()
        readiness = nil
        let wasRunning = if case .running = state { true } else { false }
        state = .stopping

        var notes: [String] = []
        if wasRunning, case .requested = reason {
            // The server installs its SIGTERM handler once it is up: let it close the engine itself first. Before
            // that point a SIGTERM would end Python alone and leave the engine behind, so startup aborts go to the group.
            do {
                try server.process.signal(SIGTERM)
            } catch {
                notes.append("SIGTERM to PID \(server.process.pid) failed: \(error.localizedDescription)")
            }
            if await waitForExit(of: server.process, within: timing.serverExitTimeout) == nil {
                notes.append("the server did not exit within \(timing.serverExitTimeout.wholeSeconds) s")
            }
        }

        let clean = await cleanupGroup(of: server)
        if clean {
            owned = nil
        }
        switch (clean, reason) {
        case (true, .requested):
            state = .stopped
        case (true, .startupTimeout):
            state = .failed("The server did not become ready within \(timing.startupDeadline.wholeSeconds) s and was stopped. See the server and engine logs.")
        case (true, .unexpectedExit(let exit)):
            state = .failed("The server exited unexpectedly (\(exit)). See the server and engine logs.")
        case (false, _):
            let detail = notes.isEmpty ? "" : " (" + notes.joined(separator: "; ") + ")"
            state = .failed("The server could not be stopped: process group \(server.process.processGroup) is still alive\(detail). Check Activity Monitor, then try Stop again.")
        }
    }

    /// SIGTERM, then SIGKILL, to whatever is left in the group; true once the group is empty.
    private func cleanupGroup(of server: OwnedServer) async -> Bool {
        let process = server.process
        if await waitForGroupGone(process, within: .zero) {
            return true
        }
        try? process.signalGroup(SIGTERM)
        if await waitForGroupGone(process, within: timing.groupTerminateTimeout) {
            return true
        }
        try? process.signalGroup(SIGKILL)
        return await waitForGroupGone(process, within: timing.groupKillTimeout)
    }

    private func waitForGroupGone(_ process: any OwnedProcess, within timeout: Duration) async -> Bool {
        await poll(within: timeout) { !process.isGroupAlive() }
    }

    private func waitForExit(of process: any OwnedProcess, within timeout: Duration) async -> ProcessExit? {
        await poll(within: timeout) { process.exitIfFinished() != nil } ? process.exitIfFinished() : nil
    }

    /// Polling instead of racing `waitForExit()` against a sleep: a task group would wait for a never-ending wait.
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
            try? await Task.sleep(for: timing.groupPollInterval)
        }
    }
}

private extension Duration {
    var wholeSeconds: Int64 { components.seconds }
}
