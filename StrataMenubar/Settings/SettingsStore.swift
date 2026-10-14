import Foundation
import Observation

/// The saved settings. They apply to the next launch; a running server keeps the settings it was started with.
@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let strataDirectory = "strataDirectory"
        static let expertCacheGB = "expertCacheGB"
        static let maxContext = "maxContext"
        static let port = "port"
    }

    private(set) var settings: StrataSettings
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.read(from: defaults)
    }

    func save(_ newSettings: StrataSettings) {
        defaults.set(newSettings.strataDirectory, forKey: Key.strataDirectory)
        defaults.set(newSettings.expertCacheGB, forKey: Key.expertCacheGB)
        defaults.set(newSettings.maxContext, forKey: Key.maxContext)
        defaults.set(newSettings.port, forKey: Key.port)
        settings = newSettings
    }

    private static func read(from defaults: UserDefaults) -> StrataSettings {
        var settings = StrataSettings.default
        if let directory = defaults.string(forKey: Key.strataDirectory) {
            settings.strataDirectory = directory
        }
        if defaults.object(forKey: Key.expertCacheGB) != nil {
            settings.expertCacheGB = defaults.double(forKey: Key.expertCacheGB)
        }
        if defaults.object(forKey: Key.maxContext) != nil {
            settings.maxContext = defaults.integer(forKey: Key.maxContext)
        }
        if defaults.object(forKey: Key.port) != nil {
            settings.port = defaults.integer(forKey: Key.port)
        }
        return settings
    }
}
