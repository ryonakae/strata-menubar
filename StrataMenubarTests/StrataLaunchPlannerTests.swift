import Foundation
import Testing
@testable import StrataMenubar

struct StrataLaunchPlannerTests {
    private func paths() -> AppPaths {
        let base = FileManager.default.temporaryDirectory.appending(path: "strata-menubar-app-\(UUID().uuidString)")
        return AppPaths(applicationSupport: base.appending(path: "support"), logs: base.appending(path: "logs"))
    }

    private func remove(_ paths: AppPaths) {
        try? FileManager.default.removeItem(at: paths.applicationSupport.deletingLastPathComponent())
    }

    private func settings(for install: TestInstallation) -> StrataSettings {
        var settings = StrataSettings.default
        settings.strataDirectory = install.root.path(percentEncoded: false)
        return settings
    }

    @Test func buildsArgumentsFromAPathWithSpacesAndJapanese() throws {
        let install = try TestInstallation.make(named: "Strata テスト dir")
        defer { install.remove() }
        let paths = paths()
        defer { remove(paths) }
        var settings = settings(for: install)
        settings.port = 8090
        settings.maxContext = 4096
        let baseBefore = try Data(contentsOf: install.baseConfig)

        let plan = try StrataLaunchPlanner(paths: paths).makePlan(settings: settings)

        #expect(plan.executable.path(percentEncoded: false) == install.python.path(percentEncoded: false))
        #expect(plan.arguments == [
            install.server.path(percentEncoded: false),
            "--engine", "strata",
            "--config", paths.runConfig(for: "q2_0").path(percentEncoded: false),
            "--host", "127.0.0.1",
            "--port", "8090",
        ])
        #expect(plan.workingDirectory.path(percentEncoded: false) == install.root.path(percentEncoded: false))
        #expect(plan.environment["PYTHONUNBUFFERED"] == "1")
        #expect(plan.standardOutputLog == paths.serverLog)
        #expect(try Data(contentsOf: install.baseConfig) == baseBefore)

        let written = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: paths.runConfig(for: "q2_0"))) as? [String: Any])
        let args = try #require(written["args"] as? [String])
        #expect(args.contains("--max-context"))
        #expect(args[args.firstIndex(of: "--max-context")! + 1] == "4096")
        #expect((written["env"] as? [String: String])?["STRATA_METAL_ARENA_GB"] == "5")
        #expect(written["log"] as? String == paths.engineLog.path(percentEncoded: false))
        #expect(written["port"] as? Int == 8090)
    }

    @Test func namesTheMissingPythonInterpreter() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try FileManager.default.removeItem(at: install.python)

        #expect {
            try StrataLaunchPlanner(paths: paths()).makePlan(settings: settings(for: install))
        } throws: { error in
            guard case LaunchPlanError.installation(let problems) = error else { return false }
            return problems.count == 1 && problems[0].contains(install.python.path(percentEncoded: false))
        }
    }

    @Test func startsWhicheverInstalledModelIsSelected() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try install.addModel(tag: "iq3_xxs", modelName: "qwen3.8-flash-next-iq3_xxs")
        let paths = paths()
        defer { remove(paths) }
        var settings = settings(for: install)
        settings.model = "iq3_xxs"

        let plan = try StrataLaunchPlanner(paths: paths).makePlan(settings: settings)

        #expect(plan.arguments.contains(paths.runConfig(for: "iq3_xxs").path(percentEncoded: false)))
        #expect(paths.runConfig(for: "iq3_xxs").lastPathComponent == "strata-iq3_xxs.run.json")
        let written = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: paths.runConfig(for: "iq3_xxs"))) as? [String: Any])
        #expect(written["model_name"] as? String == "qwen3.8-flash-next-iq3_xxs")
    }

    @Test func refusesAModelThatIsNotInstalledAndNamesTheInstalledOnes() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        var settings = settings(for: install)
        settings.model = "iq3_s"

        #expect {
            try StrataLaunchPlanner(paths: paths()).makePlan(settings: settings)
        } throws: { error in
            guard case LaunchPlanError.installation(let problems) = error else { return false }
            return problems.count == 1 && problems[0].contains("strata-iq3_s.json") && problems[0].contains("q2_0")
        }
    }

    @Test func refusesInvalidSettingsBeforeTouchingTheInstallation() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        var settings = settings(for: install)
        settings.port = 80

        #expect(throws: LaunchPlanError.self) {
            try StrataLaunchPlanner(paths: paths()).makePlan(settings: settings)
        }
    }
}
