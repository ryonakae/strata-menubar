import Foundation
import Testing
@testable import StrataMenubar

@MainActor
struct ModelInstallerTests {
    private let q2 = StrataModelCatalog.packs[0]
    private let iq3s = StrataModelCatalog.packs[2]

    @MainActor
    private final class Harness {
        let install: TestInstallation
        let paths: AppPaths
        let fake = FakeLauncher()
        let library: ModelLibrary
        let installer: ModelInstaller
        var serverRunning = false

        var process: FakeProcess? { fake.processes.last }
        var log: URL { paths.setupLog }

        init(serverRunning: Bool = false, real: Bool = false) throws {
            install = try TestInstallation.make()
            paths = AppPaths(applicationSupport: install.base.appending(path: "support"), logs: install.base.appending(path: "logs"))
            // The host's process table is another suite's business (its setup fixtures would make every pack busy).
            library = ModelLibrary(root: install.root, settingsFile: install.base.appending(path: "none.json"), watching: false, externalSetups: { _ in [] })
            self.serverRunning = serverRunning
            let flag = Flag(serverRunning)
            installer = ModelInstaller(launcher: real ? PosixProcessLauncher() : fake, paths: paths, library: library, timing: .fast)
            installer.serverIsRunning = { flag.value }
        }

        /// What the fake setup "prints": the launcher's processes write nothing, so the test appends to the log.
        func append(_ text: String) throws {
            try FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: log.path(percentEncoded: false)) {
                try Data().write(to: log)
            }
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }

        func remove() {
            install.remove()
        }
    }

    @MainActor
    private final class Flag {
        var value: Bool
        init(_ value: Bool) { self.value = value }
    }

    @Test func followsSetupThroughItsStepsToAnInstalledModel() async throws {
        let h = try Harness()
        defer { h.remove() }
        try h.append("[X]  a failure of an earlier run\n")
        let run = Task { await h.installer.download(iq3s) }
        #expect(await waitUntil { h.installer.job != nil })
        #expect(h.fake.plans == [SetupPlan.make(installation: StrataInstallation(root: h.install.root), pack: iq3s, log: h.log)])
        #expect(h.installer.job?.phase == .checking("starting setup"))
        #expect(h.installer.job?.pid == h.process?.pid)
        #expect(h.installer.ownsProcess)
        #expect(h.installer.processGroup == h.process?.processGroup)
        #expect(h.installer.quitDescription == "A download of IQ3_S (PID 1000) is running")
        #expect(h.installer.statusLine == "IQ3_S: starting setup…")

        try h.append("=== Step 1: checking your Mac ===\n")
        #expect(await waitUntil { h.installer.job?.phase == .checking("checking your Mac") })
        try h.append("=== Step 5: downloading Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S ===\n")
        try h.append("\r  \(iq3s.shardNames[0]): 1.50 / 41.80 GB (3%)")
        #expect(await waitUntil { h.installer.job?.progress == DownloadProgress(haveBytes: 1_500_000_000, totalBytes: 83_600_000_000) })
        #expect(h.installer.statusLine == "Downloading IQ3_S: 1% (1.5 / 83.6 GB)")

        // The first shard is complete and marked; the second shard's line counts on top of its size.
        let directory = h.library.dataDirectory.modelDirectory(for: iq3s)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(count: 5).write(to: directory.appending(path: iq3s.shardNames[0]))
        try Data().write(to: directory.appending(path: iq3s.shardNames[0] + ".done"))
        try h.append("\r  \(iq3s.shardNames[1]): 2.00 / 41.80 GB (4%)")
        #expect(await waitUntil { h.installer.job?.progress?.haveBytes == 2_000_000_005 })
        #expect(!h.installer.isPreparing)

        try h.append("\n=== Step 6: preparing the model for Strata ===\n")
        #expect(await waitUntil { h.installer.job?.phase == .preparing })
        #expect(h.installer.statusLine == "Preparing IQ3_S…")
        #expect(h.installer.isPreparing)
        #expect(h.process?.signals.isEmpty == true)
        try h.append("=== Step 7: writing the start script ===\n")
        try h.install.addModel(tag: "iq3_s", modelName: "qwen3.8-flash-next-iq3_s")
        h.process?.exit(with: .exited(0))
        await run.value

        #expect(h.installer.job == nil)
        #expect(h.installer.lastOutcome == .installed(iq3s))
        #expect(!h.installer.ownsProcess)
        #expect(h.installer.quitDescription == nil)
        #expect(!h.installer.isPreparing)
        #expect(h.library.installed.map(\.tag) == ["iq3_s", "q2_0"])
        #expect(h.installer.statusLine == "IQ3_S installed")
    }

    /// Setup's preparation must not run beside a server: the download is interrupted at step 6 and the pack stays downloaded.
    @Test func interruptsAtStepSixWhileAServerRunsAndReportsDownloaded() async throws {
        let h = try Harness(serverRunning: true)
        defer { h.remove() }
        h.fake.nextBehavior = FakeProcess.Behavior(exitsOnGroupSignal: [SIGINT, SIGTERM, SIGKILL])
        try h.install.addDownloadedPack(iq3s, bytesPerShard: 1)
        let run = Task { await h.installer.download(iq3s) }
        #expect(await waitUntil { h.installer.job != nil })

        try h.append("=== Step 6: preparing the model for Strata ===\n")
        await run.value
        #expect(h.process?.signals.map(\.signal) == [SIGINT])
        #expect(h.process?.signals.first?.target == .group)
        #expect(h.installer.lastOutcome == .downloaded(iq3s))
        #expect(h.installer.statusLine == "IQ3_S downloaded; it is prepared at its first start")
        #expect(!h.installer.ownsProcess)
    }

    @Test func prepareNeverInterruptsAndFailsWithoutAConfig() async throws {
        let h = try Harness(serverRunning: true)
        defer { h.remove() }
        try h.install.addDownloadedPack(iq3s)
        let run = Task { try await h.installer.prepare(iq3s) }
        #expect(await waitUntil { h.installer.job?.purpose == .prepare })
        #expect(h.installer.quitDescription == "The preparation of IQ3_S (PID 1000) is running")
        await #expect(throws: InstallError.busy) { try await h.installer.prepare(iq3s) }
        #expect(h.fake.processes.count == 1)

        try h.append("=== Step 6: preparing the model for Strata ===\n")
        #expect(await waitUntil { h.installer.job?.phase == .preparing })
        #expect(h.process?.signals.isEmpty == true)
        try h.append("[X]  a Strata engine is running\n")
        h.process?.exit(with: .exited(1))
        await #expect(throws: InstallError.failed("a Strata engine is running")) { try await run.value }
        #expect(h.installer.lastOutcome == .failed(iq3s, "a Strata engine is running"))
        #expect(h.installer.statusLine == "IQ3_S failed: a Strata engine is running. See the setup log.")
    }

    @Test func cancelEscalatesFromInterruptToKillAndKeepsTheFiles() async throws {
        let h = try Harness()
        defer { h.remove() }
        h.fake.nextBehavior = FakeProcess.Behavior(exitsOnGroupSignal: [SIGKILL], groupDiesOnSignal: [SIGKILL])
        try h.install.addPartialPack(iq3s, partBytes: 7)
        let run = Task { await h.installer.download(iq3s) }
        #expect(await waitUntil { h.installer.job != nil })
        try h.append("=== Step 5: downloading Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S ===\n")

        await h.installer.cancel()
        #expect(h.process?.signals.map(\.signal) == [SIGINT, SIGTERM, SIGKILL])
        #expect(h.process?.signals.allSatisfy { $0.target == .group } == true)
        await run.value
        #expect(h.installer.lastOutcome == .cancelled(iq3s))
        #expect(!h.installer.ownsProcess)
        #expect(h.installer.statusLine == "Setup of IQ3_S stopped; the next Download or start resumes it")
        #expect(h.library.packs[2].state == .partial(bytes: 7))
    }

    /// A group that survives even SIGKILL stays owned after its run, so that quitting still has to deal with it.
    @Test func aGroupThatOutlivesItsRunStaysOwnedAndKeepsQuitAsking() async throws {
        let h = try Harness()
        defer { h.remove() }
        h.fake.nextBehavior = FakeProcess.Behavior(exitsOnGroupSignal: [], groupSurvivesProcessExit: true, groupDiesOnSignal: [])
        let run = Task { await h.installer.download(iq3s) }
        #expect(await waitUntil { h.installer.job != nil })

        h.process?.exit(with: .exited(1))
        await run.value
        #expect(h.installer.job == nil)
        #expect(h.installer.lastOutcome == .failed(iq3s, "Setup's process group 1000 is still alive. Check Activity Monitor, then try again."))
        #expect(h.installer.ownsProcess)
        #expect(h.installer.quitDescription == "A setup process started by this app (process group 1000) may still be running")
    }

    @Test func refusesAnInstalledPackAndASecondRunAndReportsAnUnexplainedExit() async throws {
        let h = try Harness()
        defer { h.remove() }
        await h.installer.download(q2)
        #expect(h.fake.processes.isEmpty)
        #expect(h.installer.lastOutcome == nil)

        let run = Task { await h.installer.download(iq3s) }
        #expect(await waitUntil { h.installer.job != nil })
        await h.installer.download(iq3s)
        #expect(h.fake.processes.count == 1)
        // The last failure line counts even without its line break; earlier ones do not.
        try h.append("[X]  first problem\n[X]  SHA mismatch for shard 1")
        h.process?.exit(with: .exited(1))
        await run.value
        #expect(h.installer.lastOutcome == .failed(iq3s, "SHA mismatch for shard 1"))

        let plain = Task { await h.installer.download(iq3s) }
        #expect(await waitUntil { h.installer.job != nil })
        h.process?.exit(with: .exited(1))
        await plain.value
        #expect(h.installer.lastOutcome == .failed(iq3s, "Setup ended with exit status 1 before finishing."))
    }

    /// A real child: the interrupt at step 6 reaches setup, which prints "stopped." and ends; the shards stay downloaded.
    @Test func aRealSetupIsStoppedAtStepSixByTheInterrupt() async throws {
        let h = try Harness(serverRunning: true, real: true)
        defer { h.remove() }
        try h.install.addDownloadedPack(iq3s, bytesPerShard: 1)
        try Data("""
        #!/bin/sh
        trap 'echo stopped.; exit 1' INT
        echo "=== Step 5: downloading Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S ==="
        printf '\\r  %s: 1.00 / 41.80 GB (2%%)\\n' "\(iq3s.shardNames[0])"
        echo "=== Step 6: preparing the model for Strata ==="
        sleep 30
        echo "=== Step 7: writing the start script ==="

        """.utf8).write(to: h.install.python)

        await h.installer.download(iq3s)
        #expect(h.installer.lastOutcome == .downloaded(iq3s))
        #expect(!h.installer.ownsProcess)
        let output = try String(contentsOf: h.log, encoding: .utf8)
        #expect(output.contains("(2%)"))
        #expect(output.contains("stopped."))
        #expect(!output.contains("Step 7"))
    }
}
