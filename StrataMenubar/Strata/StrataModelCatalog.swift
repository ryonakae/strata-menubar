import Foundation

/// A pack Strata's setup can install on a Mac, with the sizes from Strata's docs/MAC.md and setup.py, so that the
/// guidance can say what each one needs. The list is only advice: what can be started is whatever is installed.
struct ModelPack: Identifiable, Sendable {
    var name: String
    var note: String
    /// The model file the GPU maps, in GB.
    var mappedFileGB: Double
    /// What the pack needs in memory with the prompt buffers, KV cache and draft layer; nil where it streams anyway.
    var needsAboutGB: Double?
    var recommendedFromGB: Int
    var downloadGB: Double

    var id: String { name }

    /// Strata names the config after the lower-cased pack name: `strata-ud-q4_k_xl.json`.
    var tag: String { name.lowercased() }

    func isInstalled(among installed: [InstalledModel]) -> Bool {
        installed.contains { $0.tag == tag }
    }
}

enum StrataModelCatalog {
    static let packs: [ModelPack] = [
        ModelPack(name: "Q2_0", note: "2-bit, the fastest", mappedFileGB: 37.6, needsAboutGB: 46, recommendedFromGB: 64, downloadGB: 66.4),
        ModelPack(name: "IQ3_XXS", note: "3-bit, better quality, slower", mappedFileGB: 47.0, needsAboutGB: 55, recommendedFromGB: 74, downloadGB: 75.8),
        ModelPack(name: "IQ3_S", note: "3.5-bit, the best quality, the slowest", mappedFileGB: 54.8, needsAboutGB: 63, recommendedFromGB: 96, downloadGB: 83.6),
        ModelPack(name: "UD-Q4_K_XL", note: "4-bit Unsloth Dynamic, higher quality", mappedFileGB: 82.6, needsAboutGB: 91, recommendedFromGB: 128, downloadGB: 111.3),
        ModelPack(name: "UD-Q5_K_XL", note: "5-bit Unsloth Dynamic; streams from the SSD even on 128 GB", mappedFileGB: 103.9, needsAboutGB: nil, recommendedFromGB: 128, downloadGB: 158.3),
        ModelPack(name: "UD-Q6_K_XL", note: "6-bit Unsloth Dynamic; streams from the SSD even on 128 GB", mappedFileGB: 114.8, needsAboutGB: nil, recommendedFromGB: 128, downloadGB: 169.2),
    ]
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
