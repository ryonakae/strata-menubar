import Foundation
import Testing
@testable import StrataMenubar

/// Real child processes: a shell fixture that forks a grandchild `sleep`, so a stop must end both.
struct PosixProcessLauncherTests {
    private struct Fixture {
        let directory: URL
        let script: URL
        let pidFile: URL
        let log: URL

        init(_ body: String) throws {
            directory = FileManager.default.temporaryDirectory.appending(path: "strata-menubar-proc-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            script = directory.appending(path: "fixture.sh")
            pidFile = directory.appending(path: "grandchild.pid")
            log = directory.appending(path: "logs/server.log")
            try Data(body.utf8).write(to: script)
        }

        func plan(arguments: [String] = []) -> LaunchPlan {
            LaunchPlan(
                executable: URL(filePath: "/bin/sh"),
                arguments: [script.path(percentEncoded: false), pidFile.path(percentEncoded: false)] + arguments,
                workingDirectory: directory,
                environment: ["PATH": "/usr/bin:/bin"],
                standardOutputLog: log
            )
        }

        func grandchild() async -> pid_t? {
            for _ in 0..<200 {
                if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return pid
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return nil
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static let serverLike = """
    #!/bin/sh
    sleep 300 &
    echo $! > "$1"
    exec sleep 300
    """

    private static let ignoresTerm = """
    #!/bin/sh
    trap '' TERM
    sleep 300 &
    echo $! > "$1"
    wait
    """

    private func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func waitUntilGone(_ pid: pid_t) async -> Bool {
        for _ in 0..<200 {
            if !isAlive(pid) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test func spawnsInItsOwnGroupAndAGroupSignalEndsTheDescendants() async throws {
        let fixture = try Fixture(Self.serverLike)
        defer { fixture.remove() }

        let process = try PosixProcessLauncher().launch(fixture.plan())
        let grandchild = try #require(await fixture.grandchild())
        #expect(process.processGroup == process.pid)
        #expect(getpgid(grandchild) == process.pid)
        #expect(getpgid(process.pid) != getpgrp())
        #expect(process.isGroupAlive())

        try process.signalGroup(SIGTERM)

        #expect(await process.waitForExit() == .signaled(SIGTERM))
        #expect(await waitUntilGone(grandchild))
        #expect(await waitUntil { !process.isGroupAlive() })
    }

    @Test func aGroupThatIgnoresTermStillDiesFromKill() async throws {
        let fixture = try Fixture(Self.ignoresTerm)
        defer { fixture.remove() }

        let process = try PosixProcessLauncher().launch(fixture.plan())
        let grandchild = try #require(await fixture.grandchild())

        try process.signalGroup(SIGTERM)
        try await Task.sleep(for: .milliseconds(200))
        #expect(process.isGroupAlive())
        #expect(isAlive(grandchild))
        #expect(process.exitIfFinished() == nil)

        try process.signalGroup(SIGKILL)
        #expect(await process.waitForExit() == .signaled(SIGKILL))
        #expect(await waitUntilGone(grandchild))
        #expect(await waitUntil { !process.isGroupAlive() })
    }

    @Test func redirectsOutputAndPassesArgumentsAndWorkingDirectoryUntouched() async throws {
        let fixture = try Fixture("""
        #!/bin/sh
        shift
        printf '%s\\n' "$@"
        pwd
        echo to-stderr >&2
        """)
        defer { fixture.remove() }

        let process = try PosixProcessLauncher().launch(fixture.plan(arguments: ["arg with space", "日本語 パス/x.json"]))
        #expect(await process.waitForExit() == .exited(0))

        let output = try String(contentsOf: fixture.log, encoding: .utf8)
        #expect(output.contains("arg with space\n"))
        #expect(output.contains("日本語 パス/x.json\n"))
        #expect(output.contains(fixture.directory.lastPathComponent + "\n"))
        #expect(output.contains("to-stderr\n"))
    }

    @Test func reportsTheExitStatusOfAChildThatEndsOnItsOwn() async throws {
        let fixture = try Fixture("#!/bin/sh\nexit 3\n")
        defer { fixture.remove() }
        let process = try PosixProcessLauncher().launch(fixture.plan())
        #expect(await process.waitForExit() == .exited(3))
        #expect(await waitUntil { !process.isGroupAlive() })
    }

    @MainActor
    @Test func theManagerLeavesNoDescendantsAndSparesUnrelatedProcesses() async throws {
        let fixture = try Fixture(Self.serverLike)
        defer { fixture.remove() }
        let bystander = Process()
        bystander.executableURL = URL(filePath: "/bin/sleep")
        bystander.arguments = ["300"]
        try bystander.run()
        defer { bystander.terminate() }

        let probe = FakeProbe(script: [.unreachable, .strata(.loaded())])
        let manager = ServerManager(launcher: PosixProcessLauncher(), probe: probe, planner: FixedPlanner(plan: fixture.plan()), timing: .fast)
        await manager.start(settings: .default)
        #expect(await waitUntil { manager.state.isRunning })
        let server = try #require(manager.state.runningInfo?.pid)
        let grandchild = try #require(await fixture.grandchild())

        await manager.stop()

        #expect(manager.state == .stopped)
        #expect(await waitUntilGone(server))
        #expect(await waitUntilGone(grandchild))
        #expect(bystander.isRunning)
    }

    @MainActor
    @Test func aStopDuringStartupEndsTheWholeGroup() async throws {
        let fixture = try Fixture(Self.serverLike)
        defer { fixture.remove() }

        let manager = ServerManager(launcher: PosixProcessLauncher(), probe: FakeProbe(script: [.unreachable]), planner: FixedPlanner(plan: fixture.plan()), timing: .fast)
        await manager.start(settings: .default)
        #expect(manager.state.isStarting)
        let grandchild = try #require(await fixture.grandchild())
        let server: pid_t = try #require({ if case .starting(let info) = manager.state { info.pid } else { nil } }())

        await manager.stop()

        #expect(manager.state == .stopped)
        #expect(await waitUntilGone(server))
        #expect(await waitUntilGone(grandchild))
    }
}

private struct FixedPlanner: LaunchPlanning {
    let plan: LaunchPlan

    func makePlan(settings: StrataSettings) throws -> LaunchPlan {
        plan
    }
}
