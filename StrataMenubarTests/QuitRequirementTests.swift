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
        let starting = ServerState.starting(StartingInfo(model: "q2_0", phase: .loading(pid: 42), port: 8080, since: now))
        guard case .confirmStop = QuitRequirement(state: starting, ownsProcess: true) else {
            Issue.record("starting must ask before quitting")
            return
        }
    }

    @Test func aPreparationAndADownloadAskToStopFirst() {
        let preparing = ServerState.starting(StartingInfo(model: "iq3_s", phase: .preparing, port: 8080, since: now))
        #expect(QuitRequirement(state: preparing, ownsProcess: false) == .confirmStop("The model iq3_s is being prepared for its first start"))

        let download = "A download of IQ3_S (PID 7) is running"
        let external = ExternalInfo(port: 8080, loaded: true, model: "qwen3.8-flash-next-q2_0", maxContext: 8192)
        for state in [ServerState.stopped, .stopping, .external(external), .failed("launch failed")] {
            #expect(QuitRequirement(state: state, ownsProcess: false, download: download) == .confirmStop(download))
        }
        let running = ServerState.running(RunningInfo(pid: 42, settings: .default, model: nil, maxContext: nil, since: now, health: .ok))
        #expect(QuitRequirement(state: running, ownsProcess: true, download: download)
            == .confirmStop("The server (PID 42) is running on port 8080, and a download of IQ3_S (PID 7) is running"))
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
