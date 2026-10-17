import Foundation
import Testing
@testable import StrataMenubar

struct StrataDataDirectoryTests {
    private let iq3s = StrataModelCatalog.packs[2]

    /// Setup keeps the model files where `~/.config/strata/settings.json` says, else in `Strata-data` beside the checkout.
    @Test func resolvesTheDataDirectoryLikeSetup() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let beside = install.root.deletingLastPathComponent().appending(path: "Strata-data")
        let missing = install.base.appending(path: "no-settings.json")
        #expect(StrataDataDirectory.resolve(strataRoot: install.root, settingsFile: missing).url.path(percentEncoded: false) == beside.path(percentEncoded: false))

        let elsewhere = install.base.appending(path: "elsewhere")
        let settings = try install.writeStrataSettings(dataDir: elsewhere)
        #expect(StrataDataDirectory.resolve(strataRoot: install.root, settingsFile: settings).url.path(percentEncoded: false) == elsewhere.path(percentEncoded: false))

        try Data("not json".utf8).write(to: settings)
        #expect(StrataDataDirectory.resolve(strataRoot: install.root, settingsFile: settings).url.path(percentEncoded: false) == beside.path(percentEncoded: false))
    }

    @Test func reportsWhetherAPackIsDownloadedPartialOrAbsent() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let data = StrataDataDirectory(url: install.dataDirectory)
        #expect(data.modelDirectory(for: iq3s).lastPathComponent == "IQ3_S")
        #expect(data.packState(for: iq3s) == .notDownloaded)

        try install.addPartialPack(iq3s, partBytes: 1234)
        #expect(data.packState(for: iq3s) == .partial(bytes: 1234))

        try install.addDownloadedPack(iq3s, bytesPerShard: 10)
        #expect(data.packState(for: iq3s) == .partial(bytes: 1254))

        try FileManager.default.removeItem(at: data.modelDirectory(for: iq3s).appending(path: iq3s.shardNames[0] + ".part"))
        #expect(data.packState(for: iq3s) == .downloaded)

        // The experts' copy being written during the preparation does not make the download incomplete.
        let expertsCopy = data.modelDirectory(for: iq3s).appending(path: iq3s.shardNames[0] + ".experts.part")
        try Data(count: 3).write(to: expertsCopy)
        #expect(data.packState(for: iq3s) == .downloaded)
        try FileManager.default.removeItem(at: expertsCopy)

        try FileManager.default.removeItem(at: data.modelDirectory(for: iq3s).appending(path: iq3s.shardNames[1] + ".done"))
        #expect(data.packState(for: iq3s) == .partial(bytes: 20))
    }

    @Test func freeSpaceIsReadFromTheNearestExistingDirectory() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let data = StrataDataDirectory(url: install.base.appending(path: "not/yet/created"))
        let free = try #require(data.freeBytes())
        #expect(free > 0)
    }
}
