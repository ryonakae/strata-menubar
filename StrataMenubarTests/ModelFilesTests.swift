import Foundation
import Testing
@testable import StrataMenubar

@MainActor
struct ModelFilesTests {
    private let q2 = StrataModelCatalog.packs[0]
    private let iq3s = StrataModelCatalog.packs[2]
    private let udq4 = StrataModelCatalog.packs[3]

    private struct Layout {
        let install: TestInstallation
        let paths: AppPaths
        var data: StrataDataDirectory { StrataDataDirectory(url: install.dataDirectory) }
        var installation: StrataInstallation { StrataInstallation(root: install.root) }

        init() throws {
            install = try TestInstallation.make()
            paths = AppPaths(applicationSupport: install.base.appending(path: "support"), logs: install.base.appending(path: "logs"))
        }

        func model(_ tag: String) throws -> InstalledModel {
            try #require(installation.installedModels().first { $0.tag == tag })
        }

        func write(_ bytes: Int, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: url)
        }

        func remove() {
            install.remove()
        }
    }

    private func paths(_ files: ModelFiles) -> Set<String> {
        Set(files.items.map { $0.path(percentEncoded: false) })
    }

    @Test func listsEverythingSetupWroteForAModelAndNothingShared() throws {
        let layout = try Layout()
        defer { layout.remove() }
        let shard1 = layout.install.dataDirectory.appending(path: "models/Q2_0/model-00001-of-00002.gguf")
        try layout.write(5, to: shard1)
        for suffix in [".done", ".experts", ".part"] {
            try layout.write(2, to: URL(filePath: shard1.path(percentEncoded: false) + suffix))
        }
        try layout.write(9, to: layout.install.root.appending(path: "run-q2_0.sh"))
        try layout.write(3, to: layout.install.root.appending(path: "strata-q2_0.log"))
        try layout.write(4, to: layout.paths.runConfig(for: "q2_0"))
        let configBytes = try #require(FileManager.default.attributesOfItem(atPath: layout.install.baseConfig.path(percentEncoded: false))[.size] as? Int64)

        let files = ModelFiles.forInstalled(try layout.model("q2_0"), installation: layout.installation, data: layout.data, paths: layout.paths)

        #expect(paths(files) == Set([
            layout.install.dataDirectory.appending(path: "models/Q2_0"),
            layout.install.dataDirectory.appending(path: "packs/q2_0"),
            layout.install.root.appending(path: "run-q2_0.sh"),
            layout.install.baseConfig,
            layout.install.root.appending(path: "strata-q2_0.log"),
            layout.paths.runConfig(for: "q2_0"),
        ].map { $0.path(percentEncoded: false) }))
        #expect(files.items.count == 6)
        #expect(files.totalBytes == 11 + 2 + 9 + 3 + 4 + configBytes)
        #expect(!files.items.contains { $0.path(percentEncoded: false).contains("expert-profile") })
    }

    /// A config whose files lie outside a catalog directory: the files and their marks go, the `metal/` directory stays.
    @Test func takesTheFilesAndTheirMarksButNeverTheMetalDirectory() throws {
        let layout = try Layout()
        defer { layout.remove() }
        let native = layout.install.dataDirectory.appending(path: "metal/custom-metal.gguf")
        let ple = layout.install.dataDirectory.appending(path: "other/ple.gguf")
        let pack = layout.install.dataDirectory.appending(path: "packs/custom")
        try layout.write(3, to: native)
        try layout.write(1, to: URL(filePath: native.path(percentEncoded: false) + ".done"))
        try layout.write(1, to: URL(filePath: native.path(percentEncoded: false) + ".repack.lock"))
        try layout.write(4, to: ple)
        try layout.write(1, to: URL(filePath: ple.path(percentEncoded: false) + ".experts.done"))
        try layout.write(2, to: pack.appending(path: "native_experts.txt"))
        let config: [String: Any] = [
            "model_name": "custom",
            "args": [
                "--pack", pack.path(percentEncoded: false),
                "--native", native.path(percentEncoded: false),
                "--ple-gguf", ple.path(percentEncoded: false),
                "--expert-profile", layout.install.root.appending(path: "data/expert-profile.bin").path(percentEncoded: false),
            ],
        ]
        let configURL = layout.install.configURL(for: "custom")
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)

        let files = ModelFiles.forInstalled(try layout.model("custom"), installation: layout.installation, data: layout.data, paths: layout.paths)

        #expect(paths(files) == Set([
            pack, native, URL(filePath: native.path(percentEncoded: false) + ".done"), URL(filePath: native.path(percentEncoded: false) + ".repack.lock"),
            ple, URL(filePath: ple.path(percentEncoded: false) + ".experts.done"), configURL,
        ].map { $0.path(percentEncoded: false) }))
        #expect(!files.items.contains { $0.path(percentEncoded: false).contains("expert-profile") })
        #expect(!paths(files).contains(layout.data.metal.path(percentEncoded: false)))
    }

    /// Two configs pointing at the same model files: deleting either leaves the files and the pack to the other.
    @Test func leavesWhatAnotherInstalledModelPointsAt() throws {
        let layout = try Layout()
        defer { layout.remove() }
        try layout.install.addModel(tag: "iq3_xxs", modelName: "qwen3.8-flash-next-iq3_xxs")
        try layout.write(9, to: layout.install.root.appending(path: "run-q2_0.sh"))
        // What setup leaves beside a shared file belongs to it as much as the file itself.
        let shard1 = layout.install.dataDirectory.appending(path: "models/Q2_0/model-00001-of-00002.gguf")
        try layout.write(5, to: shard1)
        for suffix in [".done", ".experts", ".experts.done"] {
            try layout.write(2, to: URL(filePath: shard1.path(percentEncoded: false) + suffix))
        }

        let copy = ModelFiles.forInstalled(try layout.model("iq3_xxs"), installation: layout.installation, data: layout.data, paths: layout.paths)
        #expect(paths(copy) == [layout.install.configURL(for: "iq3_xxs").path(percentEncoded: false)])

        let original = ModelFiles.forInstalled(try layout.model("q2_0"), installation: layout.installation, data: layout.data, paths: layout.paths)
        #expect(paths(original) == Set([layout.install.baseConfig, layout.install.root.appending(path: "run-q2_0.sh")].map { $0.path(percentEncoded: false) }))
    }

    @Test func listsADownloadedPacksDirectoryPackAndRepackedFile() throws {
        let layout = try Layout()
        defer { layout.remove() }
        try layout.install.addDownloadedPack(iq3s, bytesPerShard: 3)
        let plain = ModelFiles.forDownloaded(iq3s, installation: layout.installation, data: layout.data)
        #expect(paths(plain) == [layout.data.modelDirectory(for: iq3s).path(percentEncoded: false)])
        #expect(plain.totalBytes == 6 + 2 * 16)

        try layout.install.addDownloadedPack(udq4, bytesPerShard: 1)
        try layout.write(2, to: layout.data.packs.appending(path: "unsloth-ud-q4_k_xl/native_experts.txt"))
        let repacked = layout.data.metal.appending(path: "unsloth-ud-q4_k_xl-metal.gguf")
        try layout.write(7, to: repacked)
        try layout.write(1, to: URL(filePath: repacked.path(percentEncoded: false) + ".done"))
        let unsloth = ModelFiles.forDownloaded(udq4, installation: layout.installation, data: layout.data)
        #expect(paths(unsloth) == Set([
            layout.data.modelDirectory(for: udq4), layout.data.packs.appending(path: "unsloth-ud-q4_k_xl"),
            repacked, URL(filePath: repacked.path(percentEncoded: false) + ".done"),
        ].map { $0.path(percentEncoded: false) }))
        #expect(unsloth.totalBytes == 4 + 4 * 16 + 2 + 7 + 1)
    }

    @Test func trashMovesEveryItemAndCollectsTheFailures() throws {
        let items = [URL(filePath: "/a"), URL(filePath: "/b"), URL(filePath: "/c")]
        let files = ModelFiles(items: items, totalBytes: 0)
        var moved: [URL] = []
        try files.trash { moved.append($0) }
        #expect(moved == items)

        moved = []
        #expect(throws: ModelFiles.TrashError(failures: [.init(url: URL(filePath: "/b"), message: "refused by the test")])) {
            try files.trash { url in
                moved.append(url)
                if url.lastPathComponent == "b" { throw Refused() }
            }
        }
        #expect(moved == items)
    }

    private struct Refused: Error, LocalizedError {
        var errorDescription: String? { "refused by the test" }
    }

    @Test func aModelInUseCannotBeDeleted() throws {
        let installed = InstalledModel(tag: "q2_0", modelName: "qwen3.8-flash-next-q2_0", configURL: URL(filePath: "/x/strata-q2_0.json"))
        let status = ModelLibrary.PackStatus(pack: q2, state: .installed(installed))
        let now = Date()
        let running = ServerState.running(RunningInfo(pid: 1, settings: .default, model: "qwen3.8-flash-next-q2_0", maxContext: nil, since: now, health: .ok))
        let other = ServerState.running(RunningInfo(pid: 1, settings: .default, model: "qwen3.8-flash-next-iq3_s", maxContext: nil, since: now, health: .ok))

        #expect(status.deletionBlocker(serverState: .stopped, job: nil) == nil)
        #expect(status.deletionBlocker(serverState: .failed("x"), job: nil) == nil)
        #expect(status.deletionBlocker(serverState: other, job: nil) == nil)
        #expect(status.deletionBlocker(serverState: running, job: nil) == "the server is running it")
        #expect(status.deletionBlocker(serverState: .starting(StartingInfo(model: "q2_0", phase: .preparing, port: 1, since: now)), job: nil) == "the server is starting it")
        #expect(status.deletionBlocker(serverState: .starting(StartingInfo(model: "iq3_s", phase: .loading(pid: 2), port: 1, since: now)), job: nil) == nil)
        #expect(status.deletionBlocker(serverState: .external(ExternalInfo(port: 1, loaded: true, model: "qwen3.8-flash-next-q2_0", maxContext: nil)), job: nil) == "an external Strata server is running it")
        #expect(status.deletionBlocker(serverState: .stopping, job: nil) == "the server is stopping")
        #expect(status.deletionBlocker(serverState: .stopped, job: InstallJob(pack: q2, purpose: .download, pid: 3)) == "setup is working on it")
        #expect(status.deletionBlocker(serverState: .stopped, job: InstallJob(pack: iq3s, purpose: .download, pid: 3)) == nil)

        var busy = ModelLibrary.PackStatus(pack: iq3s, state: .downloaded)
        busy.busyElsewhere = true
        #expect(busy.deletionBlocker(serverState: .stopped, job: nil) == "a setup outside this app is working on it")
    }
}
