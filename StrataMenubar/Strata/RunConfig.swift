import Foundation

enum RunConfigError: Error, Equatable, LocalizedError {
    case notAnObject
    case missingArgs

    var errorDescription: String? {
        switch self {
        case .notAnObject: "The base config is not a JSON object."
        case .missingArgs: "The base config has no \"args\" array."
        }
    }
}

/// Derives the config the server is started with from Strata's own base config, changing only what the settings own.
enum RunConfig {
    static let maxContextFlag = "--max-context"
    static let arenaKey = "STRATA_METAL_ARENA_GB"
    static let streamKey = "STRATA_METAL_STREAM"

    static func make(base: Data, settings: StrataSettings, engineLog: URL) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: base) as? [String: Any] else {
            throw RunConfigError.notAnObject
        }
        guard var args = object["args"] as? [String] else {
            throw RunConfigError.missingArgs
        }
        var config = object

        let context = String(settings.maxContext)
        if let index = args.firstIndex(of: maxContextFlag) {
            if index + 1 < args.count {
                args[index + 1] = context
            } else {
                args.append(context)
            }
        } else {
            args += [maxContextFlag, context]
        }
        config["args"] = args

        var env = object["env"] as? [String: Any] ?? [:]
        env[arenaKey] = gigabytes(settings.expertCacheGB)
        if env[streamKey] == nil {
            env[streamKey] = "1"
        }
        config["env"] = env

        config["log"] = engineLog.path(percentEncoded: false)
        config["port"] = settings.port
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    /// The engine reads the value with atof, so "4.5" is fine and "5" is nicer than "5.00".
    static func gigabytes(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}
