import Foundation
import Testing
@testable import StrataMenubar

@MainActor
struct ModelLibraryTests {
    private let q2 = StrataModelCatalog.packs[0]
    private let iq3xxs = StrataModelCatalog.packs[1]
    private let iq3s = StrataModelCatalog.packs[2]

    private func makeLibrary(_ install: TestInstallation, watching: Bool = false) -> ModelLibrary {
        // The test layout keeps its data beside the checkout; the real settings file must not redirect it.
        ModelLibrary(root: install.root, settingsFile: install.base.appending(path: "no-settings.json"), watching: watching)
    }

    @Test func combinesTheConfigsWithThePackFiles() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try install.addDownloadedPack(iq3s)
        try install.addPartialPack(iq3xxs, partBytes: 5)
        let library = makeLibrary(install)

        #expect(library.installed.map(\.tag) == ["q2_0"])
        #expect(library.packs.map(\.pack.name) == StrataModelCatalog.packs.map(\.name))
        #expect(library.packs[0].state == .installed(library.installed[0]))
        #expect(library.packs[1].state == .partial(bytes: 5))
        #expect(library.packs[2].state == .downloaded)
        #expect(library.packs[3].state == .notDownloaded)
        #expect(library.packs.allSatisfy { !$0.busyElsewhere })
        #expect(library.freeBytes ?? 0 > 0)
        #expect(library.dataDirectory.url.path(percentEncoded: false) == install.dataDirectory.path(percentEncoded: false))
        #expect(library.downloadedPack(forTag: "iq3_s")?.name == "IQ3_S")
        #expect(library.downloadedPack(forTag: "q2_0") == nil)
        #expect(library.downloadedPack(forTag: "iq3_xxs") == nil)
    }

    /// A downloaded pack can be started (its first start prepares it); a partial or unknown one cannot.
    @Test func launchProblemsAcceptInstalledAndDownloadedModels() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try install.addDownloadedPack(iq3s)
        try install.addPartialPack(iq3xxs, partBytes: 5)
        let library = makeLibrary(install)

        #expect(library.launchProblems(for: "q2_0").isEmpty)
        #expect(library.launchProblems(for: "iq3_s").isEmpty)
        let partial = library.launchProblems(for: "iq3_xxs")
        #expect(partial.count == 1)
        #expect(partial[0].contains("strata-iq3_xxs.json"))
        #expect(partial[0].contains("Download it in Settings"))
        #expect(library.launchProblems(for: "nothing").count == 1)

        try FileManager.default.removeItem(at: install.root.appending(path: "build-metal/strata"))
        library.refresh()
        #expect(library.launchProblems(for: "q2_0").first?.contains("build-metal/strata") == true)

        // Preparing a downloaded pack needs the checkout's interpreter as much as a launch does.
        try FileManager.default.removeItem(at: install.python)
        library.refresh()
        #expect(library.launchProblems(for: "iq3_s").first?.contains("Python interpreter") == true)
    }

    @Test func noticesConfigsAndDownloadsThatAppearWhileWatching() async throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let library = makeLibrary(install, watching: true)
        #expect(library.installed.count == 1)

        try install.addModel(tag: "iq3_xxs", modelName: "qwen3.8-flash-next-iq3_xxs")
        #expect(await waitUntil { library.installed.map(\.tag) == ["iq3_xxs", "q2_0"] })

        try FileManager.default.removeItem(at: install.configURL(for: "iq3_xxs"))
        #expect(await waitUntil { library.installed.map(\.tag) == ["q2_0"] })

        // A model directory that did not exist when watching began is picked up through `models/` and then watched itself.
        try install.addDownloadedPack(iq3s, bytesPerShard: 3)
        #expect(await waitUntil { library.packs[2].state == .downloaded })
        try FileManager.default.removeItem(at: library.dataDirectory.modelDirectory(for: iq3s).appending(path: iq3s.shardNames[1] + ".done"))
        #expect(await waitUntil { library.packs[2].state == .partial(bytes: 6) })
    }

    @Test func updatingTheRootRescansWithoutWatchingTheOldOne() async throws {
        let first = try TestInstallation.make(named: "First")
        defer { first.remove() }
        let second = try TestInstallation.make(named: "Second")
        defer { second.remove() }
        try second.addModel(tag: "iq3_xxs", modelName: "qwen3.8-flash-next-iq3_xxs")
        let library = ModelLibrary(root: first.root, settingsFile: first.base.appending(path: "none.json"), watching: true)

        library.update(root: second.root)
        #expect(library.installed.map(\.tag) == ["iq3_xxs", "q2_0"])
        #expect(library.root.path(percentEncoded: false) == second.root.path(percentEncoded: false))

        try first.addModel(tag: "stale", modelName: "x")
        try? await Task.sleep(for: .milliseconds(500))
        #expect(library.installed.map(\.tag) == ["iq3_xxs", "q2_0"])
    }

    /// A setup started in a terminal is recognised by its command line; the app's own setup is told apart by its group.
    @Test func recognisesASetupRunningOutsideTheApp() async throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let fixture = install.base.appending(path: "setup_mac.py")
        try Data("#!/bin/sh\nsleep 300\n".utf8).write(to: fixture)
        let launcher = PosixProcessLauncher()
        let process = try launcher.launch(LaunchPlan(
            executable: URL(filePath: "/bin/sh"),
            arguments: [fixture.path(percentEncoded: false), "--setup", "--model", "IQ3_S", "--no-start"],
            workingDirectory: install.base,
            environment: ["PATH": "/usr/bin:/bin"],
            standardOutputLog: install.base.appending(path: "setup.log")
        ))
        defer { try? process.signalGroup(SIGKILL) }
        let library = makeLibrary(install)

        #expect(await refreshed(library) { library.packs[2].busyElsewhere })
        #expect(!library.packs[0].busyElsewhere)

        library.ownedSetupGroup = { process.processGroup }
        library.refresh()
        #expect(!library.packs[2].busyElsewhere)

        let anyModel = try launcher.launch(LaunchPlan(
            executable: URL(filePath: "/bin/sh"),
            arguments: [fixture.path(percentEncoded: false), "--setup"],
            workingDirectory: install.base,
            environment: ["PATH": "/usr/bin:/bin"],
            standardOutputLog: install.base.appending(path: "setup.log")
        ))
        defer { try? anyModel.signalGroup(SIGKILL) }
        #expect(await refreshed(library) { library.packs.allSatisfy(\.busyElsewhere) })
    }

    /// Each refresh runs pgrep, so the retries are spaced out instead of polled; the other suites share the main actor.
    private func refreshed(_ library: ModelLibrary, until condition: () -> Bool) async -> Bool {
        for _ in 0..<20 {
            library.refresh()
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
