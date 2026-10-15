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
/// A managed key is written when its setting has a value and removed otherwise, so that the run config says exactly
/// what the settings say; `--spec` is the exception, because setup always writes it and "as set up" means that value.
enum RunConfig {
    static let maxContextFlag = "--max-context"
    static let specFlag = "--spec"
    static let arenaKey = "STRATA_METAL_ARENA_GB"
    static let keepFreeKey = "STRATA_METAL_KEEP_FREE_GB"
    static let promptChunkKey = "STRATA_METAL_PROMPT_CHUNK"
    static let idleUnloadKey = "idle_unload_s"
    static let fitMaxTokensKey = "fit_max_tokens"

    static func make(base: Data, settings: StrataSettings, engineLog: URL) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: base) as? [String: Any] else {
            throw RunConfigError.notAnObject
        }
        guard var args = object["args"] as? [String] else {
            throw RunConfigError.missingArgs
        }
        var config = object

        setArgument(&args, flag: maxContextFlag, value: String(settings.maxContext))
        if let specWindow = settings.specWindow {
            setArgument(&args, flag: specFlag, value: String(specWindow))
        }
        config["args"] = args

        var env = object["env"] as? [String: Any] ?? [:]
        env[arenaKey] = settings.autoExpertCache ? nil : gigabytes(settings.expertCacheGB)
        env[keepFreeKey] = settings.autoExpertCache ? settings.keepFreeGB.map(String.init) : nil
        env[promptChunkKey] = settings.promptChunk.map(String.init)
        if object["env"] != nil || !env.isEmpty {
            config["env"] = env
        }

        config[idleUnloadKey] = settings.idleUnloadMinutes > 0 ? settings.idleUnloadMinutes * 60 : nil
        // The server accepts only the JSON literal true; a Bool serialises as that, an Int would not.
        config[fitMaxTokensKey] = settings.fitMaxTokens ? true : nil
        config["log"] = engineLog.path(percentEncoded: false)
        config["port"] = settings.port
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    /// Replaces the flag's value in place, or appends the pair when the base has no such flag.
    private static func setArgument(_ args: inout [String], flag: String, value: String) {
        if let index = args.firstIndex(of: flag) {
            if index + 1 < args.count {
                args[index + 1] = value
            } else {
                args.append(value)
            }
        } else {
            args += [flag, value]
        }
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
