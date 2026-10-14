import Foundation

/// A model set up in the Strata checkout: `strata-<tag>.json` next to the server, written by Strata's setup.
struct InstalledModel: Identifiable, Equatable, Sendable {
    var tag: String
    var modelName: String
    var configURL: URL

    var id: String { tag }
}

/// The files a launch needs from an existing Strata checkout. This app never installs, updates or edits any of them.
struct StrataInstallation: Equatable, Sendable {
    private static let fileFlags = ["--pack", "--native", "--ple-gguf", "--expert-profile"]
    private static let configPrefix = "strata-"
    private static let runConfigSuffix = ".run.json"

    let root: URL

    var python: URL { root.appending(path: ".venv/bin/python") }
    var server: URL { root.appending(path: "serve/server.py") }

    func configURL(for tag: String) -> URL {
        root.appending(path: "\(Self.configPrefix)\(tag).json")
    }

    /// Every `strata-<tag>.json` in the checkout, sorted by tag. A config that cannot be read keeps its tag as the name,
    /// so that it still shows up and the check can say what is wrong with it.
    func installedModels(fileManager fm: FileManager = .default) -> [InstalledModel] {
        guard let names = try? fm.contentsOfDirectory(atPath: root.path(percentEncoded: false)) else {
            return []
        }
        return names
            .filter { $0.hasPrefix(Self.configPrefix) && $0.hasSuffix(".json") && !$0.hasSuffix(Self.runConfigSuffix) }
            .map { name in
                let tag = String(name.dropFirst(Self.configPrefix.count).dropLast(".json".count))
                let url = root.appending(path: name)
                let object = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any]
                return InstalledModel(tag: tag, modelName: object?["model_name"] as? String ?? tag, configURL: url)
            }
            .sorted { $0.tag < $1.tag }
    }

    /// Everything a launch of the selected model would trip over, in plain words; empty when it is usable.
    func check(model tag: String, fileManager fm: FileManager = .default) -> [String] {
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
        let config = configURL(for: tag)
        guard fm.fileExists(atPath: config.path(percentEncoded: false)) else {
            let installed = installedModels(fileManager: fm).map(\.tag)
            problems.append(
                "The config for the model \"\(tag)\" is missing: \(config.path(percentEncoded: false)). "
                    + "Installed: \(installed.isEmpty ? "none" : installed.joined(separator: ", ")). "
                    + "Run Strata's setup.sh --setup --model to add a model."
            )
            return problems
        }
        do {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config))
            guard let contents = object as? [String: Any] else {
                problems.append("The config is not a JSON object: \(config.path(percentEncoded: false))")
                return problems
            }
            problems += checkContents(of: contents, fileManager: fm)
        } catch {
            problems.append("The config cannot be read: \(error.localizedDescription)")
        }
        return problems
    }

    private func checkContents(of config: [String: Any], fileManager fm: FileManager) -> [String] {
        var problems: [String] = []
        if (config["model_name"] as? String)?.isEmpty ?? true {
            problems.append("The config has no \"model_name\".")
        }
        if let exe = config["exe"] as? String {
            if !fm.isExecutableFile(atPath: exe) {
                problems.append("The engine binary is missing: \(exe)")
            }
        } else {
            problems.append("The config has no \"exe\".")
        }
        if let args = config["args"] as? [String] {
            for flag in Self.fileFlags {
                if let index = args.firstIndex(of: flag), index + 1 < args.count, !fm.fileExists(atPath: args[index + 1]) {
                    problems.append("The file for \(flag) is missing: \(args[index + 1])")
                }
            }
        } else {
            problems.append("The config has no \"args\" array.")
        }
        if let tokenizer = config["tokenizer"] as? String, !fm.fileExists(atPath: tokenizer + "/vocab.json") {
            problems.append("The tokenizer is missing: \(tokenizer)/vocab.json")
        }
        return problems
    }
}
