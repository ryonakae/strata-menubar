import Foundation

/// What a pack's files under `models/<directory>` say about its download, independent of whether a config exists.
enum PackFilesState: Equatable, Sendable {
    case notDownloaded
    /// Some shard is missing, unfinished (`.part`) or without its `.done` mark; `bytes` is what the directory holds.
    case partial(bytes: Int64)
    /// Every shard is there with its `.done` mark. The experts' copy setup writes beside shard 1 while preparing the
    /// pack (`<shard>.experts.part`, renamed when done) is not a shard, so a pack stays downloaded while that runs.
    case downloaded
}

/// Where Strata's setup keeps the model files: `data_dir` from Strata's own settings file, else `Strata-data` beside
/// the checkout (setup.py's `data_folder`). Everything here is read; setup is the only writer.
struct StrataDataDirectory: Equatable, Sendable {
    let url: URL

    /// `$XDG_CONFIG_HOME/strata/settings.json`, or `~/.config/strata/settings.json`, as setup.py's `settings_path`.
    static let defaultSettingsFile: URL = {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config")
        return base.appending(path: "strata/settings.json")
    }()

    static func resolve(strataRoot: URL, settingsFile: URL = defaultSettingsFile) -> StrataDataDirectory {
        if let data = try? Data(contentsOf: settingsFile),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let path = object["data_dir"] as? String, !path.isEmpty {
            return StrataDataDirectory(url: URL(filePath: (path as NSString).expandingTildeInPath))
        }
        return StrataDataDirectory(url: strataRoot.deletingLastPathComponent().appending(path: "Strata-data"))
    }

    var models: URL { url.appending(path: "models") }
    var packs: URL { url.appending(path: "packs") }
    /// The repacked GPU files of the Unsloth packs (and setup's lock while it prepares one).
    var metal: URL { url.appending(path: "metal") }

    func modelDirectory(for pack: ModelPack) -> URL {
        models.appending(path: pack.directoryName)
    }

    func packState(for pack: ModelPack, fileManager fm: FileManager = .default) -> PackFilesState {
        let directory = modelDirectory(for: pack)
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else {
            return .notDownloaded
        }
        // The marks are not model data: only the shards, their unfinished parts and the experts' copies count.
        let files = names.filter { $0.contains(".gguf") && !$0.hasSuffix(".done") }
        guard !files.isEmpty else {
            return .notDownloaded
        }
        let complete = pack.shardNames.allSatisfy { names.contains($0) && names.contains($0 + ".done") && !names.contains($0 + ".part") }
        if complete {
            return .downloaded
        }
        let bytes = files.reduce(Int64(0)) { sum, name in
            let attributes = try? fm.attributesOfItem(atPath: directory.appending(path: name).path(percentEncoded: false))
            return sum + Int64(truncatingIfNeeded: (attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
        return .partial(bytes: bytes)
    }

    /// The space the volume still offers for files that matter, read from the nearest directory that exists.
    func freeBytes(fileManager fm: FileManager = .default) -> Int64? {
        var probe = url
        while !fm.fileExists(atPath: probe.path(percentEncoded: false)) {
            let parent = probe.deletingLastPathComponent()
            guard parent.path(percentEncoded: false) != probe.path(percentEncoded: false) else { return nil }
            probe = parent
        }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
