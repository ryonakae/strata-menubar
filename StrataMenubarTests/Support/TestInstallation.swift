import Foundation

/// A throwaway Strata layout with the files a launch checks for and a base config in the shape setup.py writes.
struct TestInstallation {
    static let modelName = "qwen3.8-flash-next-q2_0"

    let base: URL
    let root: URL
    let dataDirectory: URL

    var python: URL { root.appending(path: ".venv/bin/python") }
    var server: URL { root.appending(path: "serve/server.py") }
    var baseConfig: URL { configURL(for: "q2_0") }

    func configURL(for tag: String) -> URL {
        root.appending(path: "strata-\(tag).json")
    }

    /// Writes another installed model's config next to the first, sharing the same model files.
    func addModel(tag: String, modelName: String) throws {
        try Self.writeConfig(to: configURL(for: tag), root: root, data: dataDirectory, modelName: modelName, includeMaxContext: true)
    }

    static func make(
        named name: String = "Strata",
        modelName: String = TestInstallation.modelName,
        includeMaxContext: Bool = true
    ) throws -> TestInstallation {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "strata-menubar-tests-\(UUID().uuidString)")
        let root = base.appending(path: name)
        let data = base.appending(path: "Strata-data")
        let install = TestInstallation(base: base, root: root, dataDirectory: data)

        for dir in [".venv/bin", "serve", "build-metal", "data"] {
            try fm.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true)
        }
        for dir in ["models/Q2_0", "packs/q2_0/tokenizer"] {
            try fm.createDirectory(at: data.appending(path: dir), withIntermediateDirectories: true)
        }
        try write("#!/bin/sh\nexit 0\n", to: install.python, executable: true)
        try write("", to: install.server)
        try write("#!/bin/sh\nexit 0\n", to: root.appending(path: "build-metal/strata"), executable: true)
        try write("", to: root.appending(path: "data/expert-profile.bin"))
        try write("", to: data.appending(path: "models/Q2_0/model-00001-of-00002.gguf"))
        try write("", to: data.appending(path: "models/Q2_0/model-00002-of-00002.gguf"))
        try write("{}", to: data.appending(path: "packs/q2_0/tokenizer/vocab.json"))

        try writeConfig(to: install.baseConfig, root: root, data: data, modelName: modelName, includeMaxContext: includeMaxContext)
        return install
    }

    private static func writeConfig(to url: URL, root: URL, data: URL, modelName: String, includeMaxContext: Bool) throws {
        var args = [
            "--pack", data.appending(path: "packs/q2_0").path(percentEncoded: false),
            "--native", data.appending(path: "models/Q2_0/model-00001-of-00002.gguf").path(percentEncoded: false),
            "--ple-gguf", data.appending(path: "models/Q2_0/model-00002-of-00002.gguf").path(percentEncoded: false),
            "--expert-profile", root.appending(path: "data/expert-profile.bin").path(percentEncoded: false),
            "--expert-cache", "64",
            "--prefill", "auto",
            "--spec", "2",
            "--suffix-draft", "0",
        ]
        if includeMaxContext {
            args += ["--max-context", "8192"]
        }
        args.append("--mmap-experts")
        let config: [String: Any] = [
            "exe": root.appending(path: "build-metal/strata").path(percentEncoded: false),
            "args": args,
            "cwd": root.path(percentEncoded: false),
            "tokenizer": data.appending(path: "packs/q2_0/tokenizer").path(percentEncoded: false),
            "model_name": modelName,
            "log": root.appending(path: "strata-q2_0.log").path(percentEncoded: false),
            "lib_dirs": [String](),
            "port": 8080,
            "backend": "metal",
            "env": ["STRATA_METAL_STREAM": "1"],
        ]
        let json = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }

    private static func write(_ text: String, to url: URL, executable: Bool = false) throws {
        try Data(text.utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
        }
    }
}
