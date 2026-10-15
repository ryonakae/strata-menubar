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

    private var fixed: StrataSettings {
        var settings = StrataSettings.default
        settings.autoExpertCache = false
        return settings
    }

    @Test func changesOnlyTheManagedKeysAndKeepsTheRest() throws {
        var settings = fixed
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
        #expect(config["idle_unload_s"] == nil)
        #expect(config["fit_max_tokens"] == nil)
        #expect(config["exe"] as? String == "/x/build-metal/strata")
        #expect(config["cwd"] as? String == "/x")
        #expect(config["tokenizer"] as? String == "/d/packs/q2_0/tokenizer")
        #expect(config["model_name"] as? String == "qwen3.8-flash-next-q2_0")
        #expect(config["backend"] as? String == "metal")
        #expect((config["lib_dirs"] as? [Any])?.isEmpty == true)
        #expect((config["custom"] as? [String: Any])?["nested"] as? Bool == true)
    }

    @Test func writesWholeGigabytesWithoutADecimalPoint() throws {
        let env = try make(fixed)["env"] as? [String: String]
        #expect(env?["STRATA_METAL_ARENA_GB"] == "5")
    }

    @Test func anAutomaticCacheLeavesTheArenaToTheEngine() throws {
        let env = try make(.default)["env"] as? [String: String]
        #expect(env == ["STRATA_METAL_STREAM": "1", "OTHER": "kept"])

        // The key is the app's: a base config that carries it would silently fix what the settings call automatic.
        let withArena = base.replacingOccurrences(of: "\"OTHER\": \"kept\"", with: "\"OTHER\": \"kept\", \"STRATA_METAL_ARENA_GB\": \"10\"")
        #expect(try make(.default, base: withArena)["env"] as? [String: String] == ["STRATA_METAL_STREAM": "1", "OTHER": "kept"])
    }

    @Test func writesTheKeptMemoryOnlyWithAnAutomaticCache() throws {
        var automatic = StrataSettings.default
        automatic.keepFreeGB = 9
        #expect((try make(automatic)["env"] as? [String: String])?["STRATA_METAL_KEEP_FREE_GB"] == "9")

        var fixedWithKeep = fixed
        fixedWithKeep.keepFreeGB = 9
        #expect((try make(fixedWithKeep)["env"] as? [String: String])?["STRATA_METAL_KEEP_FREE_GB"] == nil)

        let withKeep = base.replacingOccurrences(of: "\"OTHER\": \"kept\"", with: "\"OTHER\": \"kept\", \"STRATA_METAL_KEEP_FREE_GB\": \"5\"")
        #expect((try make(.default, base: withKeep)["env"] as? [String: String])?["STRATA_METAL_KEEP_FREE_GB"] == nil)
    }

    @Test func replacesOrAppendsTheSpecWindowAndKeepsItWhenUnset() throws {
        var window = StrataSettings.default
        window.specWindow = 3
        #expect(try make(window)["args"] as? [String] == [
            "--pack", "/d/packs/q2_0", "--spec", "3", "--suffix-draft", "0", "--max-context", "8192", "--mmap-experts",
        ])

        let noSpec = base.replacingOccurrences(of: "\"--spec\", \"2\", ", with: "")
        #expect(try make(window, base: noSpec)["args"] as? [String] == [
            "--pack", "/d/packs/q2_0", "--suffix-draft", "0", "--max-context", "8192", "--mmap-experts", "--spec", "3",
        ])

        #expect(try make(.default)["args"] as? [String] == [
            "--pack", "/d/packs/q2_0", "--spec", "2", "--suffix-draft", "0", "--max-context", "8192", "--mmap-experts",
        ])
    }

    @Test func writesThePromptChunkOnlyWhenSet() throws {
        var chunk = StrataSettings.default
        chunk.promptChunk = 2048
        #expect((try make(chunk)["env"] as? [String: String])?["STRATA_METAL_PROMPT_CHUNK"] == "2048")

        let withChunk = base.replacingOccurrences(of: "\"OTHER\": \"kept\"", with: "\"OTHER\": \"kept\", \"STRATA_METAL_PROMPT_CHUNK\": \"4096\"")
        #expect((try make(.default, base: withChunk)["env"] as? [String: String])?["STRATA_METAL_PROMPT_CHUNK"] == nil)
    }

    @Test func writesTheIdleUnloadInSecondsAndDropsItWhenNever() throws {
        var idle = StrataSettings.default
        idle.idleUnloadMinutes = 5
        #expect(try make(idle)["idle_unload_s"] as? Int == 300)

        let withIdle = base.replacingOccurrences(of: "\"port\": 8080,", with: "\"port\": 8080, \"idle_unload_s\": 600,")
        #expect(try make(.default, base: withIdle)["idle_unload_s"] == nil)
    }

    @Test func writesFitMaxTokensAsAJSONBooleanOnlyWhenOn() throws {
        var fit = StrataSettings.default
        fit.fitMaxTokens = true
        let data = try RunConfig.make(base: Data(base.utf8), settings: fit, engineLog: URL(filePath: "/logs/engine.log"))
        // The server only accepts the JSON literal true, not 1.
        #expect(String(decoding: data, as: UTF8.self).contains("\"fit_max_tokens\" : true"))

        let withFit = base.replacingOccurrences(of: "\"port\": 8080,", with: "\"port\": 8080, \"fit_max_tokens\": true,")
        #expect(try make(.default, base: withFit)["fit_max_tokens"] == nil)
    }

    @Test func appendsMaxContextWhenTheBaseHasNone() throws {
        let noContext = base.replacingOccurrences(of: "\"--max-context\", \"8192\", ", with: "")
        let args = try make(.default, base: noContext)["args"] as? [String]
        #expect(args == ["--pack", "/d/packs/q2_0", "--spec", "2", "--suffix-draft", "0", "--mmap-experts", "--max-context", "8192"])
    }

    @Test func leavesTheStreamingChoiceToTheBase() throws {
        let noEnv = base.replacingOccurrences(of: "\"env\": {\"STRATA_METAL_STREAM\": \"1\", \"OTHER\": \"kept\"},", with: "")
        #expect(try make(.default, base: noEnv)["env"] == nil)
        #expect(try make(fixed, base: noEnv)["env"] as? [String: String] == ["STRATA_METAL_ARENA_GB": "5"])
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
