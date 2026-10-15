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

    @Test func aConfigWithoutAModelNameIsListedByTagAndFailsTheCheck() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        var contents = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: install.baseConfig)) as? [String: Any])
        contents.removeValue(forKey: "model_name")
        try JSONSerialization.data(withJSONObject: contents).write(to: install.configURL(for: "noname"))
        let installation = StrataInstallation(root: install.root)

        #expect(installation.installedModels().first { $0.tag == "noname" }?.modelName == "noname")
        let problems = installation.check(model: "noname")
        #expect(problems.count == 1)
        #expect(problems[0].contains("model_name"))
    }

    @Test func reportsAConfigWhoseFilesAreGone() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try FileManager.default.removeItem(at: install.root.appending(path: "build-metal/strata"))

        let problems = StrataInstallation(root: install.root).check(model: "q2_0")
        #expect(problems.count == 1)
        #expect(problems[0].contains("build-metal/strata"))
    }

    @Test func readsWhatTheBaseConfigSaysAboutSpecMTPAndStreaming() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let installation = StrataInstallation(root: install.root)
        #expect(installation.baseFacts(for: "q2_0") == BaseConfigFacts(specWindow: 2, hasMTP: false, streaming: true))

        var contents = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: install.baseConfig)) as? [String: Any])
        var args = try #require(contents["args"] as? [String])
        args[args.firstIndex(of: "--spec")! + 1] = "3"
        args += ["--mtp", "/d/mtp.bin"]
        contents["args"] = args
        contents["env"] = ["STRATA_METAL_STREAM": "0"]
        try JSONSerialization.data(withJSONObject: contents).write(to: install.configURL(for: "resident"))
        #expect(installation.baseFacts(for: "resident") == BaseConfigFacts(specWindow: 3, hasMTP: true, streaming: false))

        contents["args"] = args.filter { !["--spec", "3", "--mtp", "/d/mtp.bin"].contains($0) }
        contents.removeValue(forKey: "env")
        try JSONSerialization.data(withJSONObject: contents).write(to: install.configURL(for: "bare"))
        #expect(installation.baseFacts(for: "bare") == BaseConfigFacts(specWindow: nil, hasMTP: false, streaming: nil))

        #expect(installation.baseFacts(for: "missing") == nil)
    }
}
