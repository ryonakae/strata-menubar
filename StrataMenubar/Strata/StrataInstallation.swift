import Foundation

/// The files a launch needs from an existing Strata checkout. This app never installs, updates or edits any of them.
struct StrataInstallation: Equatable, Sendable {
    static let modelName = "qwen3.8-flash-next-q2_0"
    static let baseConfigName = "strata-q2_0.json"
    private static let fileFlags = ["--pack", "--native", "--ple-gguf", "--expert-profile"]

    let root: URL

    var python: URL { root.appending(path: ".venv/bin/python") }
    var server: URL { root.appending(path: "serve/server.py") }
    var baseConfig: URL { root.appending(path: Self.baseConfigName) }

    /// Everything a launch would trip over, in plain words; empty when the installation is usable.
    func check(fileManager fm: FileManager = .default) -> [String] {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else {
            return ["The Strata directory does not exist: \(root.path(percentEncoded: false))"]
        }
        var problems: [String] = []
        if !fm.isExecutableFile(atPath: python.path(percentEncoded: false)) {
            problems.append("The Python interpreter is missing (run Strata's setup.sh): \(python.path(percentEncoded: false))")
        }
        if !fm.fileExists(atPath: server.path(percentEncoded: false)) {
            problems.append("The server script is missing: \(server.path(percentEncoded: false))")
        }
        guard fm.fileExists(atPath: baseConfig.path(percentEncoded: false)) else {
            problems.append("The base config is missing (run Strata's setup.sh): \(baseConfig.path(percentEncoded: false))")
            return problems
        }
        do {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: baseConfig))
            guard let config = object as? [String: Any] else {
                problems.append("The base config is not a JSON object: \(baseConfig.path(percentEncoded: false))")
                return problems
            }
            problems += checkContents(of: config, fileManager: fm)
        } catch {
            problems.append("The base config cannot be read: \(error.localizedDescription)")
        }
        return problems
    }

    private func checkContents(of config: [String: Any], fileManager fm: FileManager) -> [String] {
        var problems: [String] = []
        let model = config["model_name"] as? String
        if model != Self.modelName {
            problems.append("The base config is for \"\(model ?? "an unknown model")\", but this app only runs \(Self.modelName).")
        }
        if let exe = config["exe"] as? String {
            if !fm.isExecutableFile(atPath: exe) {
                problems.append("The engine binary is missing: \(exe)")
            }
        } else {
            problems.append("The base config has no \"exe\".")
        }
        if let args = config["args"] as? [String] {
            for flag in Self.fileFlags {
                if let index = args.firstIndex(of: flag), index + 1 < args.count, !fm.fileExists(atPath: args[index + 1]) {
                    problems.append("The file for \(flag) is missing: \(args[index + 1])")
                }
            }
        } else {
            problems.append("The base config has no \"args\" array.")
        }
        if let tokenizer = config["tokenizer"] as? String, !fm.fileExists(atPath: tokenizer + "/vocab.json") {
            problems.append("The tokenizer is missing: \(tokenizer)/vocab.json")
        }
        return problems
    }
}
