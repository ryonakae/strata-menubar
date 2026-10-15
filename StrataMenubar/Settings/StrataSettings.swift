import Foundation

/// What the user can change. The values are checked here; whether they work on the machine is only known after a launch.
struct StrataSettings: Equatable, Codable, Sendable {
    var strataDirectory: String
    /// The stem of the installed config to start: `strata-q2_0.json` is the model `q2_0`.
    var model: String
    var expertCacheGB: Double
    var maxContext: Int
    var port: Int

    static let `default` = StrataSettings(
        strataDirectory: "~/Strata",
        model: "q2_0",
        expertCacheGB: 5,
        maxContext: 8192,
        port: 8080
    )

    var strataDirectoryURL: URL {
        let trimmed = strataDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(filePath: (trimmed as NSString).expandingTildeInPath)
    }

    var hasErrors: Bool {
        validate().contains { $0.severity == .error }
    }

    func validate(memory: MemoryBudget = .current) -> [SettingsIssue] {
        var issues: [SettingsIssue] = []
        if strataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.error("The Strata directory is empty."))
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.error("No model is selected."))
        }
        if !expertCacheGB.isFinite || expertCacheGB <= 0 {
            issues.append(.error("The expert cache must be a positive number of gigabytes."))
        } else if expertCacheGB < 2 {
            issues.append(.warning(
                "Caches under 2 GB are likely to fail: the engine needs about 1.36 GB of the arena for a prompt's buffers, "
                    + "and at about 0.8 GB it stopped with \"no arena region for the prompt buffers\"."
            ))
        } else if expertCacheGB > Double(memory.cacheWarningAboveGB) {
            issues.append(.warning(
                "Caches over half of this Mac's \(memory.physicalMemoryGiB) GiB leave little for the engine's other memory "
                    + "and macOS; expect swapping. The value is kept as you set it."
            ))
        }
        if maxContext <= 0 {
            issues.append(.error("The context must be a positive number of tokens."))
        } else if maxContext > 8192 {
            issues.append(.warning("Contexts over 8192 are untested here and raise memory use."))
        }
        if !(1024...65535).contains(port) {
            issues.append(.error("The port must be between 1024 and 65535."))
        }
        return issues
    }
}

/// What the running Mac's memory allows the expert cache to be, so that no threshold from one machine is hard-coded.
struct MemoryBudget: Equatable, Sendable {
    let physicalMemoryGiB: Int

    init(physicalMemoryBytes: UInt64) {
        physicalMemoryGiB = max(1, Int(physicalMemoryBytes >> 30))
    }

    static let current = MemoryBudget(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)

    var cacheRange: ClosedRange<Int> { 1...physicalMemoryGiB }

    /// A cache above this many GB (more than half the memory) gets a warning.
    var cacheWarningAboveGB: Int { (physicalMemoryGiB + 1) / 2 }
}

/// The context sizes offered in the menu and on the slider.
enum ContextSteps {
    static let values = [1024, 2048, 4096, 8192, 16384, 32768]

    /// The step closest to a value, so that a saved context outside the list still lands somewhere on the slider.
    static func nearestIndex(to value: Int) -> Int {
        var best = 0
        for (index, step) in values.enumerated() where abs(step - value) < abs(values[best] - value) {
            best = index
        }
        return best
    }
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
