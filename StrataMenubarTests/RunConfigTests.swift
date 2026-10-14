import Foundation
import Testing
@testable import StrataMenubar

struct RunConfigTests {
    private let base = """
    {
      "exe": "/x/build-metal/strata",
      "args": ["--pack", "/d/packs/q2_0", "--spec", "2", "--suffix-draft", "0", "--max-context", "8192", "--mmap-experts"],
      "cwd": "/x",
      "tokenizer": "/d/packs/q2_0/tokenizer",
      "model_name": "qwen3.8-flash-next-q2_0",
      "log": "/x/strata-q2_0.log",
      "lib_dirs": [],
      "port": 8080,
      "backend": "metal",
      "env": {"STRATA_METAL_STREAM": "1", "OTHER": "kept"},
      "custom": {"nested": true}
    }
    """

    private func make(_ settings: StrataSettings, base: String? = nil) throws -> [String: Any] {
        let data = try RunConfig.make(
            base: Data((base ?? self.base).utf8),
            settings: settings,
            engineLog: URL(filePath: "/logs/engine.log")
        )
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func changesOnlyTheManagedKeysAndKeepsTheRest() throws {
        var settings = StrataSettings.default
        settings.maxContext = 4096
        settings.expertCacheGB = 4.5
        settings.port = 8090

        let config = try make(settings)
        #expect(config["args"] as? [String] == [
            "--pack", "/d/packs/q2_0", "--spec", "2", "--suffix-draft", "0", "--max-context", "4096", "--mmap-experts",
        ])
        #expect(config["env"] as? [String: String] == [
            "STRATA_METAL_STREAM": "1", "OTHER": "kept", "STRATA_METAL_ARENA_GB": "4.5",
        ])
        #expect(config["log"] as? String == "/logs/engine.log")
        #expect(config["port"] as? Int == 8090)
        #expect(config["exe"] as? String == "/x/build-metal/strata")
        #expect(config["cwd"] as? String == "/x")
        #expect(config["tokenizer"] as? String == "/d/packs/q2_0/tokenizer")
        #expect(config["model_name"] as? String == "qwen3.8-flash-next-q2_0")
        #expect(config["backend"] as? String == "metal")
        #expect((config["lib_dirs"] as? [Any])?.isEmpty == true)
        #expect((config["custom"] as? [String: Any])?["nested"] as? Bool == true)
    }

    @Test func writesWholeGigabytesWithoutADecimalPoint() throws {
        let env = try make(.default)["env"] as? [String: String]
        #expect(env?["STRATA_METAL_ARENA_GB"] == "5")
    }

    @Test func appendsMaxContextWhenTheBaseHasNone() throws {
        let noContext = base.replacingOccurrences(of: "\"--max-context\", \"8192\", ", with: "")
        let args = try make(.default, base: noContext)["args"] as? [String]
        #expect(args == ["--pack", "/d/packs/q2_0", "--spec", "2", "--suffix-draft", "0", "--mmap-experts", "--max-context", "8192"])
    }

    @Test func addsTheStreamFlagWhenTheBaseEnvLacksIt() throws {
        let noEnv = base.replacingOccurrences(of: "\"env\": {\"STRATA_METAL_STREAM\": \"1\", \"OTHER\": \"kept\"},", with: "")
        let env = try make(.default, base: noEnv)["env"] as? [String: String]
        #expect(env == ["STRATA_METAL_STREAM": "1", "STRATA_METAL_ARENA_GB": "5"])
    }

    @Test func rejectsABaseWithoutAnArgsArray() {
        #expect(throws: RunConfigError.self) {
            try make(.default, base: "{\"exe\": \"/x\"}")
        }
        #expect(throws: RunConfigError.self) {
            try make(.default, base: "[1, 2]")
        }
    }
}
