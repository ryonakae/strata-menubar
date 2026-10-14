import Foundation
import Testing
@testable import StrataMenubar

@MainActor
struct ServerManagerTests {
    private let settings = StrataSettings.default

    private struct Harness {
        let launcher = FakeLauncher()
        let planner = FakePlanner()
        let probe: FakeProbe
        let manager: ServerManager

        @MainActor
        init(probe: FakeProbe) {
            self.probe = probe
            manager = ServerManager(launcher: launcher, probe: probe, planner: planner, timing: .fast)
        }

        var process: FakeProcess? { launcher.processes.last }
    }

    @Test func startSpawnsOneProcessAndRunsOnceTheModelIsLoaded() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loading), .strata(.loaded())]))
        var custom = settings
        custom.port = 8090

        await h.manager.start(settings: custom)

        #expect(h.manager.state.isStarting)
        #expect(h.launcher.processes.count == 1)
        #expect(h.launcher.plans == [FakePlanner.plan(for: custom)])
        #expect(h.planner.received == [custom])
        #expect(await waitUntil { h.manager.state.isRunning })
        let info = h.manager.state.runningInfo
        #expect(info?.pid == h.process?.pid)
        #expect(info?.settings == custom)
        #expect(info?.port == 8090)
        #expect(info?.model == "qwen3.8-flash-next-q2_0")
        #expect(info?.maxContext == 8192)
        #expect(info?.health == .ok)
        #expect(h.manager.ownsProcess)
    }

    @Test func repeatedStartsNeverSpawnASecondProcess() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loading)]))

        async let first: Void = h.manager.start(settings: settings)
        async let second: Void = h.manager.start(settings: settings)
        async let third: Void = h.manager.start(settings: settings)
        _ = await (first, second, third)
        await h.manager.start(settings: settings)

        #expect(h.launcher.processes.count == 1)
        #expect(h.manager.state.isStarting)
    }

    @Test func anExternalServerIsShownAndNeverSignaled() async {
        let h = Harness(probe: FakeProbe(script: [.strata(.loaded())]))

        await h.manager.start(settings: settings)
        #expect(h.manager.state == .external(ExternalInfo(port: 8080, loaded: true, model: "qwen3.8-flash-next-q2_0", maxContext: 8192)))
        #expect(h.launcher.processes.isEmpty)
        #expect(!h.manager.ownsProcess)

        await h.manager.stop()
        #expect(h.manager.state == .external(ExternalInfo(port: 8080, loaded: true, model: "qwen3.8-flash-next-q2_0", maxContext: 8192)))

        h.probe.setScript([.unreachable])
        await h.manager.refresh(port: 8080)
        #expect(h.manager.state == .stopped)
    }

    @Test func refreshNoticesAnExternalServerWhileStopped() async {
        let h = Harness(probe: FakeProbe(script: [.strata(.loading)]))
        await h.manager.refresh(port: 8080)
        #expect(h.manager.state == .external(ExternalInfo(port: 8080, loaded: false, model: "qwen3.8-flash-next-q2_0", maxContext: 0)))
    }

    @Test func aForeignServiceOnThePortIsAConflict() async {
        let h = Harness(probe: FakeProbe(script: [.occupied("another service answered")]))
        await h.manager.start(settings: settings)
        #expect(h.manager.state.failureMessage?.contains("another service answered") == true)
        #expect(h.launcher.processes.isEmpty)
        #expect(h.manager.canStart)
    }

    @Test func plannerAndLauncherFailuresAreReportedWithoutOwnership() async {
        let refused = Harness(probe: FakeProbe())
        refused.planner.error = .installation(["The Python interpreter is missing: /x/.venv/bin/python"])
        await refused.manager.start(settings: settings)
        #expect(refused.manager.state.failureMessage?.contains("/x/.venv/bin/python") == true)
        #expect(refused.launcher.processes.isEmpty)
        #expect(!refused.manager.ownsProcess)

        let broken = Harness(probe: FakeProbe())
        broken.launcher.failsToLaunch = true
        await broken.manager.start(settings: settings)
        #expect(broken.manager.state.failureMessage?.contains("spawn refused by the test") == true)
        #expect(!broken.manager.ownsProcess)
        #expect(broken.manager.canStart)
    }

    @Test func aLateHealthAnswerFromAnAbandonedLaunchDoesNotPromoteTheNextOne() async {
        let h = Harness(probe: FakeProbe(manual: true))

        async let firstStart: Void = h.manager.start(settings: settings)
        await h.probe.resolveNext(.unreachable)
        await firstStart
        let first = h.process
        #expect(h.manager.state.isStarting)

        await h.manager.stop()
        #expect(h.manager.state == .stopped)
        #expect(first?.hasExited == true)

        // The abandoned readiness probe is still pending at index 0; the new launch's pre-check arrives behind it.
        async let secondStart: Void = h.manager.start(settings: settings)
        await h.probe.resolve(.unreachable, at: 1)
        await secondStart
        let second = h.process
        #expect(h.launcher.processes.count == 2)
        #expect(second?.pid != first?.pid)

        await h.probe.resolveNext(.strata(.loaded()))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(h.manager.state.isStarting)
        #expect(second?.hasExited == false)

        await h.probe.resolveNext(.strata(.loaded()))
        #expect(await waitUntil { h.manager.state.isRunning })
        #expect(h.manager.state.runningInfo?.pid == second?.pid)
    }

    @Test func anExitDuringStartupFailsAndCleansUpTheGroup() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loading)]))
        h.launcher.nextBehavior = FakeProcess.Behavior(groupSurvivesProcessExit: true)
        await h.manager.start(settings: settings)

        h.process?.exit(with: .exited(1))

        #expect(await waitUntil { h.manager.state.isFailed })
        #expect(h.manager.state.failureMessage?.contains("exit status 1") == true)
        #expect(h.process?.signals.map(\.target) == [.group])
        #expect(h.process?.signals.first?.signal == SIGTERM)
        #expect(!h.manager.ownsProcess)
        #expect(h.launcher.processes.count == 1)
        #expect(h.manager.canStart)
    }

    @Test func aStartupThatNeverBecomesReadyIsStoppedAndReported() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable]))
        await h.manager.start(settings: settings)

        #expect(await waitUntil { h.manager.state.isFailed })
        #expect(h.manager.state.failureMessage?.contains("did not become ready") == true)
        #expect(h.process?.signals.first.map { $0.target == .group && $0.signal == SIGTERM } == true)
        #expect(h.process?.hasExited == true)
        #expect(!h.manager.ownsProcess)
        #expect(h.launcher.processes.count == 1)
    }

    @Test func aRequestedStopAsksTheServerFirst() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loaded())]))
        await h.manager.start(settings: settings)
        #expect(await waitUntil { h.manager.state.isRunning })

        await h.manager.stop()

        #expect(h.manager.state == .stopped)
        #expect(h.process?.signals.map(\.target) == [.process])
        #expect(h.process?.signals.first?.signal == SIGTERM)
        #expect(!h.manager.ownsProcess)
        #expect(h.manager.canStart)
    }

    @Test func aLingeringEngineIsTerminatedThenKilled() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loaded())]))
        h.launcher.nextBehavior = FakeProcess.Behavior(groupSurvivesProcessExit: true, groupDiesOnSignal: [SIGKILL])
        await h.manager.start(settings: settings)
        #expect(await waitUntil { h.manager.state.isRunning })

        await h.manager.stop()

        #expect(h.manager.state == .stopped)
        let signals = h.process?.signals ?? []
        #expect(signals.map(\.target) == [.process, .group, .group])
        #expect(signals.map(\.signal) == [SIGTERM, SIGTERM, SIGKILL])
        #expect(!h.manager.ownsProcess)
    }

    @Test func aFailedStopKeepsOwnershipAndRefusesARestart() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loaded())]))
        h.launcher.nextBehavior = .immortal
        await h.manager.start(settings: settings)
        #expect(await waitUntil { h.manager.state.isRunning })

        await h.manager.stop()

        #expect(h.manager.state.failureMessage?.contains("could not be stopped") == true)
        #expect(h.manager.ownsProcess)
        #expect(!h.manager.canStart)
        guard case .confirmStop = h.manager.quitRequirement else {
            Issue.record("quitting must still ask while the process remains")
            return
        }
        await h.manager.start(settings: settings)
        #expect(h.launcher.processes.count == 1)
    }

    @Test func aStopDuringStartupSignalsTheWholeGroupNotJustTheServer() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loading)]))
        await h.manager.start(settings: settings)
        #expect(h.manager.state.isStarting)

        await h.manager.stop()

        #expect(h.manager.state == .stopped)
        #expect(h.process?.signals.first.map { $0.target == .group && $0.signal == SIGTERM } == true)
        #expect(h.process?.signals.contains { $0.target == .process } == false)
        #expect(!h.manager.ownsProcess)
    }

    @Test func anUnexpectedExitWhileRunningIsReportedAndNotRestarted() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loaded())]))
        await h.manager.start(settings: settings)
        #expect(await waitUntil { h.manager.state.isRunning })

        h.process?.exit(with: .signaled(9))

        #expect(await waitUntil { h.manager.state.isFailed })
        #expect(h.manager.state.failureMessage?.contains("signal 9") == true)
        #expect(h.launcher.processes.count == 1)
        #expect(!h.manager.ownsProcess)
        #expect(h.manager.canStart)
    }

    @Test func restartStopsTheOldServerAndStartsWithTheNewSettings() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loaded()), .unreachable, .strata(.loaded(maxContext: 4096))]))
        await h.manager.start(settings: settings)
        #expect(await waitUntil { h.manager.state.isRunning })
        let old = h.process
        var changed = settings
        changed.maxContext = 4096

        await h.manager.restart(settings: changed)

        #expect(old?.signals.first.map { $0.target == .process && $0.signal == SIGTERM } == true)
        #expect(h.launcher.processes.count == 2)
        #expect(await waitUntil { h.manager.state.isRunning })
        #expect(h.manager.state.runningInfo?.settings == changed)
        #expect(h.manager.state.runningInfo?.pid == h.process?.pid)
        #expect(h.planner.received == [settings, changed])
    }

    @Test func aHealthFailureWhileRunningIsReportedWithoutARestart() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loaded())]))
        await h.manager.start(settings: settings)
        #expect(await waitUntil { h.manager.state.isRunning })

        h.probe.setScript([.unreachable])
        h.manager.startMonitoring { 8080 }

        #expect(await waitUntil { h.manager.state.runningInfo?.health == .unreachable })
        #expect(h.manager.state.isRunning)
        #expect(h.launcher.processes.count == 1)
        #expect(h.process?.signals.isEmpty == true)
        h.manager.stopMonitoring()
    }

    @Test func waitForIdleReturnsOnceAStopHasFinished() async {
        let h = Harness(probe: FakeProbe(script: [.unreachable, .strata(.loaded())]))
        h.launcher.nextBehavior = FakeProcess.Behavior(exitsOnProcessSignal: [], exitsOnGroupSignal: [SIGKILL], groupDiesOnSignal: [SIGKILL])
        await h.manager.start(settings: settings)
        #expect(await waitUntil { h.manager.state.isRunning })

        let stop = Task { await h.manager.stop() }
        #expect(await waitUntil { h.manager.state == .stopping })
        #expect(h.manager.quitRequirement == .waitForStop)

        await h.manager.waitForIdle()

        #expect(h.manager.state == .stopped)
        await stop.value
    }
}
