import Foundation

/// A pack Strata's setup can install on a Mac, with the sizes from Strata's docs/MAC.md, setup.py and
/// metal/setup_mac.py, so that the guidance can say what each one needs. The list is only advice: what can be started
/// is whatever is installed.
struct ModelPack: Identifiable, Equatable, Sendable {
    enum Family: Equatable, Sendable {
        case qwen
        case unsloth
    }

    var name: String
    var family: Family
    var note: String
    /// How many GGUF files setup downloads; the Unsloth packs cut through layers and are repacked for the GPU.
    var shards: Int
    /// The model file the GPU maps, in GB (for an Unsloth pack the repacked file, not a download).
    var mappedFileGB: Double
    /// What the pack needs in memory with the prompt buffers, KV cache and draft layer; nil where it streams anyway.
    var needsAboutGB: Double?
    var recommendedFromGB: Int
    var downloadGB: Double
    /// The experts' streaming copy a Mac under 96 GB writes beside shard 1 (setup.py's `arena_gb`), in GB.
    var expertsCopyGB: Double

    var id: String { name }

    /// Setup prefixes the Unsloth family's files: `strata-unsloth-ud-q4_k_xl.json`, `models/unsloth-UD-Q4_K_XL`.
    private var familyPrefix: String {
        switch family {
        case .qwen: ""
        case .unsloth: "unsloth-"
        }
    }

    /// The stem of the config setup writes: `strata-<tag>.json`.
    var tag: String { familyPrefix + name.lowercased() }

    /// The directory under the data directory's `models/` that holds the shards.
    var directoryName: String { familyPrefix + name }

    /// The shard file names in order, as setup.py's family patterns produce them.
    var shardNames: [String] {
        (1...shards).map { index in
            let numbering = "\(Self.pad(index))-of-\(Self.pad(shards))"
            return switch family {
            case .qwen: "Qwen3.8-Flash-Next-GSQ-RCO-\(name)-\(numbering).gguf"
            case .unsloth: "Qwen3.8-Flash-Next-\(name)-\(numbering).gguf"
            }
        }
    }

    func isInstalled(among installed: [InstalledModel]) -> Bool {
        installed.contains { $0.tag == tag }
    }

    /// Setup's rule (metal/setup_mac.py `streams`): the mapped file plus 8 GB of overhead against what Metal lets one
    /// process keep resident, three quarters of the memory, and on a Mac of 64 GB or more at most 70% of it.
    func streams(memory: MemoryBudget) -> Bool {
        let ramGB = Double(memory.physicalMemoryBytes) / Double(1 << 30)
        let gibInGB = 1.073741824
        var budget = ramGB * 0.75 * gibInGB
        if ramGB >= 64 {
            budget = min(budget, ramGB * gibInGB * 0.7)
        }
        return mappedFileGB + 8 > budget
    }

    /// What a finished setup leaves on the disk: the download, the repacked file of an Unsloth pack, the experts'
    /// copy on a streaming Mac under 96 GB, and the pack (about 1.5 GB).
    func diskEstimateGB(memory: MemoryBudget) -> Double {
        var total = downloadGB + 1.5
        if family == .unsloth {
            total += mappedFileGB
        }
        if streams(memory: memory), Double(memory.physicalMemoryBytes) / Double(1 << 30) < 96 {
            total += expertsCopyGB
        }
        return total
    }

    /// The estimate plus the 10 GB setup wants to spare after the experts' copy.
    func requiredFreeGB(memory: MemoryBudget) -> Double {
        diskEstimateGB(memory: memory) + 10
    }

    private static func pad(_ value: Int) -> String {
        String(format: "%05d", value)
    }
}

enum StrataModelCatalog {
    static let packs: [ModelPack] = [
        ModelPack(name: "Q2_0", family: .qwen, note: "2-bit, the fastest", shards: 2, mappedFileGB: 37.6, needsAboutGB: 46, recommendedFromGB: 64, downloadGB: 66.4, expertsCopyGB: 34.0),
        ModelPack(name: "IQ3_XXS", family: .qwen, note: "3-bit, better quality, slower", shards: 2, mappedFileGB: 47.0, needsAboutGB: 55, recommendedFromGB: 74, downloadGB: 75.8, expertsCopyGB: 42.9),
        ModelPack(name: "IQ3_S", family: .qwen, note: "3.5-bit, the best quality, the slowest", shards: 2, mappedFileGB: 54.8, needsAboutGB: 63, recommendedFromGB: 96, downloadGB: 83.6, expertsCopyGB: 50.3),
        ModelPack(name: "UD-Q4_K_XL", family: .unsloth, note: "4-bit Unsloth Dynamic, higher quality", shards: 4, mappedFileGB: 82.6, needsAboutGB: 91, recommendedFromGB: 128, downloadGB: 111.3, expertsCopyGB: 77.0),
        ModelPack(name: "UD-Q5_K_XL", family: .unsloth, note: "5-bit Unsloth Dynamic; streams from the SSD even on 128 GB", shards: 6, mappedFileGB: 103.9, needsAboutGB: nil, recommendedFromGB: 128, downloadGB: 158.3, expertsCopyGB: 98.4),
        ModelPack(name: "UD-Q6_K_XL", family: .unsloth, note: "6-bit Unsloth Dynamic; streams from the SSD even on 128 GB", shards: 6, mappedFileGB: 114.8, needsAboutGB: nil, recommendedFromGB: 128, downloadGB: 169.2, expertsCopyGB: 109.2),
    ]

    static func pack(forTag tag: String) -> ModelPack? {
        packs.first { $0.tag == tag }
    }
}

/// The shell command that installs another model with Strata's own setup. `--no-start` keeps setup from starting a
/// server of its own, which this app would only see as an external one.
enum SetupCommand {
    static func make(strataDirectory: String, model: String) -> String {
        let path = (strataDirectory.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let quoted = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "cd \"\(quoted)\" && ./setup.sh --setup --model \(model) --no-start"
    }
}
