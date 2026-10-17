import Foundation

/// What deleting a model moves to the Trash: everything setup wrote for it that no other installed model uses. The
/// shared things (`data/expert-profile.bin`, `mtp/`, the engine, `.venv`, the `metal/` directory itself) are never
/// listed, and a file another installed config points at stays, together with the model directory that holds it.
struct ModelFiles: Equatable, Sendable {
    struct TrashError: Error, LocalizedError, Equatable {
        struct Failure: Equatable {
            var url: URL
            var message: String
        }

        var failures: [Failure]

        var errorDescription: String? {
            "Could not be moved to the Trash: " + failures.map { "\($0.url.lastPathComponent) (\($0.message))" }.joined(separator: ", ")
        }
    }

    /// Sorted by path; nothing here lies inside another item.
    var items: [URL]
    var totalBytes: Int64

    private static let fileFlags = ["--native", "--ple-gguf"]
    /// What setup leaves beside a model file: the download mark, the experts' copy and its mark, an unfinished
    /// download, and the repack's lock.
    private static let siblingSuffixes = [".done", ".experts", ".experts.done", ".part", ".repack.lock"]

    static func forInstalled(
        _ model: InstalledModel,
        installation: StrataInstallation,
        data: StrataDataDirectory,
        paths: AppPaths,
        fileManager fm: FileManager = .default
    ) -> ModelFiles {
        let references = references(in: model.configURL)
        var candidates = references.pack.map { [$0] } ?? []
        for file in references.files {
            candidates.append(file)
            candidates += siblings(of: file)
        }
        if let pack = StrataModelCatalog.pack(forTag: model.tag) {
            candidates.append(data.modelDirectory(for: pack))
        }
        candidates += [
            model.configURL,
            installation.root.appending(path: "run-\(model.tag).sh"),
            installation.root.appending(path: "strata-\(model.tag).log"),
            paths.runConfig(for: model.tag),
        ]
        return make(candidates, shared: sharedPaths(installation: installation, except: model.tag), fileManager: fm)
    }

    /// A pack without a config: its model directory, a pack setup may have made, and an Unsloth pack's repacked file.
    static func forDownloaded(
        _ pack: ModelPack,
        installation: StrataInstallation,
        data: StrataDataDirectory,
        fileManager fm: FileManager = .default
    ) -> ModelFiles {
        var candidates = [data.modelDirectory(for: pack), data.packs.appending(path: pack.tag)]
        if pack.family == .unsloth {
            let repacked = data.metal.appending(path: "\(pack.tag)-metal.gguf")
            candidates += [repacked] + siblings(of: repacked)
        }
        return make(candidates, shared: sharedPaths(installation: installation, except: nil), fileManager: fm)
    }

    /// Moves every item to the Trash, carrying on after a failure and reporting all of them at the end.
    func trash(using move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        var failures: [TrashError.Failure] = []
        for item in items {
            do {
                try move(item)
            } catch {
                failures.append(TrashError.Failure(url: item, message: error.localizedDescription))
            }
        }
        if !failures.isEmpty {
            throw TrashError(failures: failures)
        }
    }

    // MARK: - Building the list

    private static func make(_ candidates: [URL], shared: [String], fileManager fm: FileManager) -> ModelFiles {
        var seen = Set<String>()
        let existing = candidates.filter { url in
            let path = normalized(url)
            guard fm.fileExists(atPath: path), !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
        // Anything equal to, inside, or holding a path another config needs stays, the holder being its model directory.
        let own = existing.filter { item in
            let path = normalized(item)
            return !shared.contains { path == $0 || isInside(path, $0) || isInside($0, path) }
        }
        let paths = own.map(normalized)
        let items = own.filter { item in
            let path = normalized(item)
            return !paths.contains { $0 != path && isInside(path, $0) }
        }
        .sorted { normalized($0) < normalized($1) }
        return ModelFiles(items: items, totalBytes: items.reduce(0) { $0 + size(of: $1, fileManager: fm) })
    }

    /// The paths every other installed config points at, with what setup left beside its files: a shared shard
    /// needs its mark and its experts' copy as much as itself.
    private static func sharedPaths(installation: StrataInstallation, except tag: String?) -> [String] {
        installation.installedModels().filter { $0.tag != tag }.flatMap { model -> [String] in
            let references = references(in: model.configURL)
            let files = references.files.flatMap { [$0] + siblings(of: $0) }
            return ((references.pack.map { [$0] } ?? []) + files).map(normalized)
        }
    }

    private static func references(in config: URL) -> (pack: URL?, files: [URL]) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(contentsOf: config))) as? [String: Any],
              let args = object["args"] as? [String] else {
            return (nil, [])
        }
        func value(of flag: String) -> URL? {
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return URL(filePath: args[index + 1])
        }
        return (value(of: "--pack"), fileFlags.compactMap(value(of:)))
    }

    private static func siblings(of file: URL) -> [URL] {
        siblingSuffixes.map { URL(filePath: normalized(file) + $0) }
    }

    private static func normalized(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func isInside(_ path: String, _ directory: String) -> Bool {
        path.hasPrefix(directory + "/")
    }

    private static func size(of url: URL, fileManager fm: FileManager) -> Int64 {
        var isDirectory: ObjCBool = false
        let path = normalized(url)
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return ((try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let entries = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let entry as URL in entries {
            let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}

extension ModelLibrary.PackStatus {
    /// Why the pack must be left alone right now; nil when it may be deleted. A model is in use while this app's
    /// server runs or starts it (the preparation included), while an external Strata serves it, and while a stop is
    /// under way, which no longer says which model it is.
    func deletionBlocker(serverState: ServerState, job: InstallJob?) -> String? {
        if busyElsewhere {
            return "a setup outside this app is working on it"
        }
        if let job, job.pack == pack {
            return "setup is working on it"
        }
        switch serverState {
        case .running(let info) where servesThisModel(info.model):
            return "the server is running it"
        case .starting(let info) where info.model == pack.tag:
            return "the server is starting it"
        case .external(let info) where servesThisModel(info.model):
            return "an external Strata server is running it"
        case .stopping:
            return "the server is stopping"
        case .running, .starting, .external, .stopped, .failed:
            return nil
        }
    }

    private func servesThisModel(_ name: String?) -> Bool {
        guard let name, case .installed(let model) = state else { return false }
        return model.modelName == name
    }
}
