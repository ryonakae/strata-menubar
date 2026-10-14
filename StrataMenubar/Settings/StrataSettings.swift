import Foundation

/// What the user can change. The values are checked here; whether they work on the machine is only known after a launch.
struct StrataSettings: Equatable, Codable, Sendable {
    var strataDirectory: String
    var expertCacheGB: Double
    var maxContext: Int
    var port: Int

    static let `default` = StrataSettings(
        strataDirectory: "~/Dev/local/Strata",
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

    func validate() -> [SettingsIssue] {
        var issues: [SettingsIssue] = []
        if strataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.error("The Strata directory is empty."))
        }
        if !expertCacheGB.isFinite || expertCacheGB <= 0 {
            issues.append(.error("The expert cache must be a positive number of gigabytes."))
        } else if expertCacheGB < 3 {
            issues.append(.warning(
                "Caches under 3 GB are untested: at about 0.8 GB the engine failed with "
                    + "\"no arena region for the prompt buffers\". 5 GB is known to work."
            ))
        } else if expertCacheGB > 12 {
            issues.append(.warning(
                "Caches over 12 GB are untested on this Mac. The engine's footprint was about 10.6 GB with a 5 GB cache; "
                    + "a larger cache can push macOS into swapping."
            ))
        }
        if maxContext <= 0 {
            issues.append(.error("The context must be a positive number of tokens."))
        } else if maxContext > 8192 {
            issues.append(.warning(
                "Contexts over 8192 are untested here and raise memory use. Update contextWindow in Pi's models.json to match."
            ))
        } else if maxContext < 2048 {
            issues.append(.warning(
                "Contexts under 2048 cannot hold a reply of Pi's maxTokens (2048). Update Pi's models.json to match."
            ))
        }
        if !(1024...65535).contains(port) {
            issues.append(.error("The port must be between 1024 and 65535."))
        }
        return issues
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
