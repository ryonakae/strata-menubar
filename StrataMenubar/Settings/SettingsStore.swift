import Foundation
import Observation

/// The saved settings. They apply to the next launch; a running server keeps the settings it was started with.
@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let strataDirectory = "strataDirectory"
        static let model = "model"
        static let autoExpertCache = "autoExpertCache"
        static let expertCacheGB = "expertCacheGB"
        static let keepFreeGB = "keepFreeGB"
        static let maxContext = "maxContext"
        static let port = "port"
        static let idleUnloadMinutes = "idleUnloadMinutes"
        static let specWindow = "specWindow"
        static let promptChunk = "promptChunk"
        static let fitMaxTokens = "fitMaxTokens"
    }

    private(set) var settings: StrataSettings
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.read(from: defaults)
    }

    func save(_ newSettings: StrataSettings) {
        defaults.set(newSettings.strataDirectory, forKey: Key.strataDirectory)
        defaults.set(newSettings.model, forKey: Key.model)
        defaults.set(newSettings.autoExpertCache, forKey: Key.autoExpertCache)
        defaults.set(newSettings.expertCacheGB, forKey: Key.expertCacheGB)
        Self.set(newSettings.keepFreeGB, forKey: Key.keepFreeGB, in: defaults)
        defaults.set(newSettings.maxContext, forKey: Key.maxContext)
        defaults.set(newSettings.port, forKey: Key.port)
        defaults.set(newSettings.idleUnloadMinutes, forKey: Key.idleUnloadMinutes)
        Self.set(newSettings.specWindow, forKey: Key.specWindow, in: defaults)
        Self.set(newSettings.promptChunk, forKey: Key.promptChunk, in: defaults)
        defaults.set(newSettings.fitMaxTokens, forKey: Key.fitMaxTokens)
        settings = newSettings
    }

    /// An absent optional is removed, so that it never reads back as a stale number.
    private static func set(_ value: Int?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func read(from defaults: UserDefaults) -> StrataSettings {
        var settings = StrataSettings.default
        if let directory = defaults.string(forKey: Key.strataDirectory) {
            settings.strataDirectory = directory
        }
        if let model = defaults.string(forKey: Key.model) {
            settings.model = model
        } else {
            settings.model = defaultModel(in: settings.strataDirectoryURL)
        }
        if defaults.object(forKey: Key.autoExpertCache) != nil {
            settings.autoExpertCache = defaults.bool(forKey: Key.autoExpertCache)
        } else if defaults.object(forKey: Key.expertCacheGB) != nil {
            // A cache saved before the automatic mode existed was a deliberate fixed size.
            settings.autoExpertCache = false
        }
        if defaults.object(forKey: Key.expertCacheGB) != nil {
            settings.expertCacheGB = defaults.double(forKey: Key.expertCacheGB)
        }
        if defaults.object(forKey: Key.keepFreeGB) != nil {
            settings.keepFreeGB = defaults.integer(forKey: Key.keepFreeGB)
        }
        if defaults.object(forKey: Key.maxContext) != nil {
            settings.maxContext = defaults.integer(forKey: Key.maxContext)
        }
        if defaults.object(forKey: Key.port) != nil {
            settings.port = defaults.integer(forKey: Key.port)
        }
        if defaults.object(forKey: Key.idleUnloadMinutes) != nil {
            settings.idleUnloadMinutes = defaults.integer(forKey: Key.idleUnloadMinutes)
        }
        if defaults.object(forKey: Key.specWindow) != nil {
            settings.specWindow = defaults.integer(forKey: Key.specWindow)
        }
        if defaults.object(forKey: Key.promptChunk) != nil {
            settings.promptChunk = defaults.integer(forKey: Key.promptChunk)
        }
        if defaults.object(forKey: Key.fitMaxTokens) != nil {
            settings.fitMaxTokens = defaults.bool(forKey: Key.fitMaxTokens)
        }
        return settings
    }

    /// Without a saved choice: q2_0 when it is installed (or nothing is), otherwise the first installed model.
    private static func defaultModel(in root: URL) -> String {
        let installed = StrataInstallation(root: root).installedModels()
        let preferred = StrataSettings.default.model
        if installed.isEmpty || installed.contains(where: { $0.tag == preferred }) {
            return preferred
        }
        return installed[0].tag
    }
}
