import Foundation
import Testing
@testable import StrataMenubar

/// Drives the real Strata installation through the same components the app uses. It is skipped unless
/// `.build/real-strata.json` exists in the repository (environment variables do not reach app-hosted tests): it loads
/// the model, which takes minutes and about 10 GB, and uses the app's real log and config locations. An optional
/// `"continueDir"` in that file names a directory where the test waits for `<phase>.continue` while the server is
/// up, so an operator can inspect it from outside.
@MainActor
struct RealStrataIntegrationTests {
    private nonisolated static let optIn: [String: String]? = {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appending(path: ".build/real-strata.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
    }()
    private nonisolated static var enabled: Bool { optIn != nil }
    private nonisolated static var continueDirectory: URL? { optIn?["continueDir"].map { URL(filePath: $0) } }
    private nonisolated static let loadTimeout: Duration = .seconds(900)

    @Test(.enabled(if: enabled), .timeLimit(.minutes(60)))
    func startsAnswersAppliesSettingsAndStops() async throws {
        let paths = AppPaths.standard
        let manager = ServerManager(
            launcher: PosixProcessLauncher(),
            probe: URLSessionHealthProbe(),
            planner: StrataLaunchPlanner(paths: paths)
        )
        let settings = StrataSettings.default
        note("memory before start:\n\(memoryReport())")

        let started = ContinuousClock.now
        await manager.start(settings: settings)
        #expect(manager.state.isStarting, "state after start: \(manager.state)")
        #expect(await waitUntil(timeout: Self.loadTimeout) { manager.state.isRunning || manager.state.isFailed })
        let first = try #require(manager.state.runningInfo, "state: \(manager.state)")
        note("running: pid \(first.pid), model \(first.model ?? "?"), context \(first.maxContext ?? 0), after \(ContinuousClock.now - started)")
        #expect(first.model == StrataInstallation.modelName)
        #expect(first.maxContext == 8192)
        #expect(first.settings == settings)
        #expect(await URLSessionHealthProbe().probe(port: 8080) == .strata(StrataHealth(loaded: true, model: StrataInstallation.modelName, maxContext: 8192)))

        let answer = try await ask("Reply with the single word: pong", port: 8080)
        note("answer: \(answer)")
        #expect(!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        note("memory after load and one answer:\n\(memoryReport())")
        await pause("running-1")

        // Saving alone changes nothing: the same process keeps serving.
        try await Task.sleep(for: .seconds(2))
        #expect(manager.state.runningInfo?.pid == first.pid)

        var changed = settings
        changed.maxContext = 4096
        let restarted = ContinuousClock.now
        await manager.restart(settings: changed)
        #expect(await waitUntil(timeout: Self.loadTimeout) { manager.state.isRunning || manager.state.isFailed })
        let second = try #require(manager.state.runningInfo, "state: \(manager.state)")
        note("restarted: pid \(second.pid), context \(second.maxContext ?? 0), after \(ContinuousClock.now - restarted)")
        #expect(second.pid != first.pid)
        #expect(second.maxContext == 4096)
        #expect(second.settings == changed)
        #expect(!isAlive(first.pid))
        await pause("running-2")

        await manager.stop()
        #expect(manager.state == .stopped, "state after stop: \(manager.state)")
        #expect(!manager.ownsProcess)
        #expect(!isAlive(second.pid))
        #expect(await URLSessionHealthProbe().probe(port: 8080) == .unreachable)
        note("memory after stop:\n\(memoryReport())")
    }

    private func ask(_ question: String, port: Int) async throws -> String {
        var request = URLRequest(url: URL(string: "http://\(StrataEndpoint.host):\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": StrataInstallation.modelName,
            "messages": [["role": "user", "content": question]],
            "max_tokens": 64,
            "stream": false,
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let choices = try #require(object["choices"] as? [[String: Any]])
        let message = try #require(choices.first?["message"] as? [String: Any])
        return try #require(message["content"] as? String)
    }

    /// Leaves the server up until `<phase>.continue` appears (or 20 minutes pass) so an operator can inspect it.
    private func pause(_ phase: String) async {
        guard let directory = Self.continueDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let waiting = directory.appending(path: "\(phase).waiting")
        let proceed = directory.appending(path: "\(phase).continue")
        try? Data().write(to: waiting)
        note("paused at \(phase); create \(proceed.path(percentEncoded: false)) to continue")
        let deadline = ContinuousClock.now + .seconds(1200)
        while !FileManager.default.fileExists(atPath: proceed.path(percentEncoded: false)), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func memoryReport() -> String {
        [run("/usr/sbin/sysctl", ["vm.swapusage"]), run("/usr/bin/memory_pressure", [])]
            .joined(separator: "\n")
            .split(separator: "\n")
            .filter { $0.contains("swapusage") || $0.contains("percentage") || $0.contains("Pageouts") || $0.contains("Swapins") || $0.contains("Swapouts") }
            .joined(separator: "\n")
    }

    private func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return "\(executable): \(error.localizedDescription)"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func note(_ text: String) {
        print("[real-strata] \(text)")
    }
}
