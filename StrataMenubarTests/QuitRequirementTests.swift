import Foundation
import Testing
@testable import StrataMenubar

struct QuitRequirementTests {
    private let now = Date(timeIntervalSince1970: 0)

    @Test func stoppedAndExternalQuitImmediately() {
        #expect(QuitRequirement(state: .stopped, ownsProcess: false) == .none)
        let external = ExternalInfo(port: 8080, loaded: true, model: "qwen3.8-flash-next-q2_0", maxContext: 8192)
        #expect(QuitRequirement(state: .external(external), ownsProcess: false) == .none)
    }

    @Test func runningAndStartingAskToStopFirst() {
        let running = ServerState.running(RunningInfo(pid: 42, settings: .default, model: nil, maxContext: nil, since: now, health: .ok))
        guard case .confirmStop = QuitRequirement(state: running, ownsProcess: true) else {
            Issue.record("running must ask before quitting")
            return
        }
        let starting = ServerState.starting(StartingInfo(pid: 42, port: 8080, since: now))
        guard case .confirmStop = QuitRequirement(state: starting, ownsProcess: true) else {
            Issue.record("starting must ask before quitting")
            return
        }
    }

    @Test func stoppingWaitsForTheStopToFinish() {
        #expect(QuitRequirement(state: .stopping, ownsProcess: true) == .waitForStop)
    }

    @Test func failedStopStillAsksWhileAProcessRemains() {
        guard case .confirmStop = QuitRequirement(state: .failed("stop failed"), ownsProcess: true) else {
            Issue.record("a failed stop with a live process must ask before quitting")
            return
        }
        #expect(QuitRequirement(state: .failed("launch failed"), ownsProcess: false) == .none)
    }
}
