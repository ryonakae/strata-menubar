import Foundation
import Testing
@testable import StrataMenubar

struct StrataInstallationTests {
    @Test func listsEveryStrataConfigSortedByTagAndSkipsRunConfigs() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try install.addModel(tag: "iq3_xxs", modelName: "qwen3.8-flash-next-iq3_xxs")
        try Data("not json".utf8).write(to: install.configURL(for: "broken"))
        try Data("{}".utf8).write(to: install.root.appending(path: "strata-q2_0.run.json"))
        try Data("{}".utf8).write(to: install.root.appending(path: "other.json"))

        let models = StrataInstallation(root: install.root).installedModels()

        #expect(models.map(\.tag) == ["broken", "iq3_xxs", "q2_0"])
        #expect(models.map(\.modelName) == ["broken", "qwen3.8-flash-next-iq3_xxs", "qwen3.8-flash-next-q2_0"])
        #expect(models[2].configURL.lastPathComponent == "strata-q2_0.json")
    }

    @Test func anEmptyDirectoryListsNothing() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try FileManager.default.removeItem(at: install.baseConfig)
        #expect(StrataInstallation(root: install.root).installedModels().isEmpty)
        #expect(StrataInstallation(root: install.root.appending(path: "missing")).installedModels().isEmpty)
    }

    @Test func checksTheSelectedModelAndAcceptsAnyInstalledOne() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try install.addModel(tag: "iq3_xxs", modelName: "qwen3.8-flash-next-iq3_xxs")
        let installation = StrataInstallation(root: install.root)

        #expect(installation.check(model: "q2_0").isEmpty)
        #expect(installation.check(model: "iq3_xxs").isEmpty)

        let missing = installation.check(model: "ud-q4_k_xl")
        #expect(missing.count == 1)
        #expect(missing[0].contains("strata-ud-q4_k_xl.json"))
        #expect(missing[0].contains("iq3_xxs, q2_0"))
    }

    @Test func reportsAConfigWhoseFilesAreGone() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try FileManager.default.removeItem(at: install.root.appending(path: "build-metal/strata"))

        let problems = StrataInstallation(root: install.root).check(model: "q2_0")
        #expect(problems.count == 1)
        #expect(problems[0].contains("build-metal/strata"))
    }
}
