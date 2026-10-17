import Foundation

/// What the user can change. The values are checked here; whether they work on the machine is only known after a launch.
struct StrataSettings: Equatable, Codable, Sendable {
    var strataDirectory: String
    /// The stem of the installed config to start: `strata-q2_0.json` is the model `q2_0`.
    var model: String
    /// Whether the engine sizes the expert arena itself; `expertCacheGB` is the fixed size used otherwise.
    var autoExpertCache: Bool
    var expertCacheGB: Double
    /// Memory left to macOS while the engine sizes the arena; nil keeps the engine's own rule.
    var keepFreeGB: Int?
    var maxContext: Int
    var port: Int
    /// 0: the model stays loaded.
    var idleUnloadMinutes: Int
    /// The MTP drafter's verify window; nil keeps what setup wrote into the base config.
    var specWindow: Int?
    /// nil: the engine chooses by memory and by whether the experts stream.
    var promptChunk: Int?
    var fitMaxTokens: Bool

    static let `default` = StrataSettings(
        strataDirectory: "~/Strata",
        model: "q2_0",
        autoExpertCache: true,
        expertCacheGB: 5,
        keepFreeGB: nil,
        maxContext: 8192,
        port: 8080,
        idleUnloadMinutes: 0,
        specWindow: nil,
        promptChunk: nil,
        fitMaxTokens: false
    )

    var strataDirectoryURL: URL {
        let trimmed = strataDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(filePath: (trimmed as NSString).expandingTildeInPath)
    }

    var hasErrors: Bool {
        validate().contains { $0.severity == .error }
    }

    /// The settings as a launch sees them: a value the cache mode leaves unused is reset, so that two settings compare
    /// equal when they start the same server and nobody is asked to restart for nothing.
    var effective: StrataSettings {
        var copy = self
        if autoExpertCache {
            copy.expertCacheGB = Self.default.expertCacheGB
        } else {
            copy.keepFreeGB = nil
        }
        return copy
    }

    /// `base` is what the selected model's config already says; without it the checks that depend on it are skipped.
    func validate(memory: MemoryBudget = .current, base: BaseConfigFacts? = nil) -> [SettingsIssue] {
        var issues: [SettingsIssue] = []
        if strataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.error("The Strata directory is empty."))
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.error("No model is selected."))
        }
        if autoExpertCache {
            issues += validateKeepFree(memory: memory)
        } else {
            issues += validateFixedCache(memory: memory)
        }
        if maxContext <= 0 {
            issues.append(.error("The context must be a positive number of tokens."))
        } else if maxContext > 32768 {
            issues.append(.warning(
                "Contexts over 32768 are untested by Strata: it measured the Mac engine to 32K and its setup offers up to 128K. "
                    + "The KV cache grows with the context: on a 32 GiB Mac the engine allocated 7.0 GB before the expert arena "
                    + "at 262144 against 3.7 GB at 32768 (about 14.5 KB per token), memory an automatic arena gives up. "
                    + "The value is kept as you set it."
            ))
        }
        if !(1024...65535).contains(port) {
            issues.append(.error("The port must be between 1024 and 65535."))
        }
        if idleUnloadMinutes < 0 {
            issues.append(.error("The idle unload must be never (0) or a number of minutes."))
        }
        if let specWindow {
            issues += validateSpecWindow(specWindow, base: base)
        }
        if let promptChunk {
            issues += validatePromptChunk(promptChunk, memory: memory, base: base)
        }
        return issues
    }

    private func validateFixedCache(memory: MemoryBudget) -> [SettingsIssue] {
        if !expertCacheGB.isFinite || expertCacheGB <= 0 {
            return [.error("The expert cache must be a positive number of gigabytes.")]
        }
        if expertCacheGB < 2 {
            return [.warning(
                "Caches under 2 GB are likely to fail: the engine needs about 1.36 GB of the arena for a prompt's buffers, "
                    + "and at about 0.8 GB it stopped with \"no arena region for the prompt buffers\"."
            )]
        }
        if expertCacheGB > Double(memory.cacheWarningAboveGB) {
            return [.warning(
                "Caches over half of this Mac's \(memory.physicalMemoryGiB) GiB leave little for the engine's other memory "
                    + "and macOS; expect swapping. The value is kept as you set it."
            )]
        }
        return []
    }

    private func validateKeepFree(memory: MemoryBudget) -> [SettingsIssue] {
        guard let keepFreeGB else { return [] }
        if !memory.cacheRange.contains(keepFreeGB) {
            return [.error("The memory kept for macOS must be between 1 and \(memory.physicalMemoryGiB) GB.")]
        }
        if Double(keepFreeGB) < EngineDefaults.keepFreeFloorGB {
            return [.warning(
                "Keeping less than 7 GB for macOS has swapped: a 34-minute server run that kept 5 GB swapped out 93 MB while "
                    + "the arena filled, so Strata's own floor is 7 GB. The value is kept as you set it."
            )]
        }
        return []
    }

    private func validateSpecWindow(_ window: Int, base: BaseConfigFacts?) -> [SettingsIssue] {
        guard SpecWindow.range.contains(window) else {
            return [.error("The verify window must be between \(SpecWindow.range.lowerBound) and \(SpecWindow.range.upperBound) tokens.")]
        }
        var issues: [SettingsIssue] = []
        if window >= 5 {
            issues.append(.warning("Windows of 5 or more measured slower than 2 to 4 on an M5 Max (Strata's docs). The value is kept as you set it."))
        }
        if let base, !base.hasMTP {
            issues.append(.warning("This model's config has no MTP draft layer (--mtp), so --spec has no effect until setup adds one."))
        }
        return issues
    }

    private func validatePromptChunk(_ chunk: Int, memory: MemoryBudget, base: BaseConfigFacts?) -> [SettingsIssue] {
        guard chunk >= 64, chunk <= 8192, chunk % 64 == 0 else {
            return [.error("The prompt chunk must be a multiple of 64 between 64 and 8192 tokens.")]
        }
        if let base, base.streaming == true, let engine = EngineDefaults.promptChunk(memory: memory, streaming: true), chunk > engine {
            return [.warning(
                "Chunks above this Mac's default of \(engine) take their buffers from the expert arena while a prompt runs "
                    + "(4.3 GB at 4096, measured by Strata). The value is kept as you set it."
            )]
        }
        return []
    }
}

/// What the running Mac's memory allows the expert cache to be, so that no threshold from one machine is hard-coded.
struct MemoryBudget: Equatable, Sendable {
    let physicalMemoryBytes: UInt64
    let physicalMemoryGiB: Int

    init(physicalMemoryBytes: UInt64) {
        self.physicalMemoryBytes = physicalMemoryBytes
        physicalMemoryGiB = max(1, Int(physicalMemoryBytes >> 30))
    }

    static let current = MemoryBudget(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)

    /// The gigabytes a fixed cache, or the memory kept for macOS, may be.
    var cacheRange: ClosedRange<Int> { 1...physicalMemoryGiB }

    /// A cache above this many GB (more than half the memory) gets a warning.
    var cacheWarningAboveGB: Int { (physicalMemoryGiB + 1) / 2 }
}

/// The context sizes offered on the slider.
enum ContextSteps {
    static let values = [1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144]

    /// The step closest to a value, so that a saved context outside the list still lands somewhere on the slider.
    static func nearestIndex(to value: Int) -> Int {
        var best = 0
        for (index, step) in values.enumerated() where abs(step - value) < abs(values[best] - value) {
            best = index
        }
        return best
    }
}

/// The idle unload choices; 0 is never. The server checks every N/4 s (at most 30 s), so finer steps mean nothing.
enum IdleUnloadSteps {
    static let minutes = [0, 5, 10, 15, 30, 60, 120]
}

/// The prompt chunk choices: the sizes Strata measured, and the engine's upper bound.
enum PromptChunkSteps {
    static let values = [1024, 2048, 4096, 8192]
}

/// The MTP verify window the engine accepts: below 2 the drafter is off, 8 is the verify kernels' cap (kVerifyMaxT).
enum SpecWindow {
    static let range = 2...8
}

struct SettingsIssue: Equatable, Sendable, Identifiable {
    enum Severity: Sendable {
        case error
        case warning
    }

    var severity: Severity
    var message: String

    var id: String { message }

    static func error(_ message: String) -> SettingsIssue {
        SettingsIssue(severity: .error, message: message)
    }

    static func warning(_ message: String) -> SettingsIssue {
        SettingsIssue(severity: .warning, message: message)
    }
}
