import Foundation
import Testing
@testable import StrataMenubar

@MainActor
struct SettingsStoreTests {
    @Test func startsFromTheDefaultsAndRoundTripsThroughUserDefaults() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let suite = "StrataMenubarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // The directory is pinned so that the test never looks at the developer's real Strata checkout.
        defaults.set(install.root.path(percentEncoded: false), forKey: "strataDirectory")
        var expected = StrataSettings.default
        expected.strataDirectory = install.root.path(percentEncoded: false)

        let store = SettingsStore(defaults: defaults)
        #expect(store.settings == expected)

        var changed = StrataSettings.default
        changed.strataDirectory = "/tmp/Strata テスト dir"
        changed.model = "iq3_xxs"
        changed.autoExpertCache = false
        changed.expertCacheGB = 4.5
        changed.keepFreeGB = 9
        changed.maxContext = 4096
        changed.port = 8090
        changed.idleUnloadMinutes = 10
        changed.specWindow = 3
        changed.promptChunk = 2048
        changed.fitMaxTokens = true
        store.save(changed)

        #expect(store.settings == changed)
        #expect(SettingsStore(defaults: defaults).settings == changed)

        // Back to the engine's own choices: the optional values must read back as absent, not as stale numbers.
        var cleared = changed
        cleared.autoExpertCache = true
        cleared.keepFreeGB = nil
        cleared.idleUnloadMinutes = 0
        cleared.specWindow = nil
        cleared.promptChunk = nil
        cleared.fitMaxTokens = false
        store.save(cleared)

        #expect(store.settings == cleared)
        #expect(SettingsStore(defaults: defaults).settings == cleared)
    }

    @Test func aCacheSavedBeforeTheAutomaticModeExistedStaysFixed() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let suite = "StrataMenubarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(install.root.path(percentEncoded: false), forKey: "strataDirectory")
        defaults.set(4.5, forKey: "expertCacheGB")

        let settings = SettingsStore(defaults: defaults).settings
        #expect(!settings.autoExpertCache)
        #expect(settings.expertCacheGB == 4.5)
    }

    @Test func settingsSavedBeforeModelSelectionExistedReadAsQ2_0() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let suite = "StrataMenubarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(install.root.path(percentEncoded: false), forKey: "strataDirectory")
        defaults.set(8090, forKey: "port")

        let settings = SettingsStore(defaults: defaults).settings
        #expect(settings.port == 8090)
        #expect(settings.model == "q2_0")
    }

    @Test func withoutASavedModelTheFirstInstalledOneStandsInWhenQ2_0IsAbsent() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        try FileManager.default.removeItem(at: install.baseConfig)
        try install.addModel(tag: "ud-q4_k_xl", modelName: "qwen3.8-flash-next-ud-q4_k_xl")
        try install.addModel(tag: "iq3_xxs", modelName: "qwen3.8-flash-next-iq3_xxs")
        let suite = "StrataMenubarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(install.root.path(percentEncoded: false), forKey: "strataDirectory")

        #expect(SettingsStore(defaults: defaults).settings.model == "iq3_xxs")

        try FileManager.default.removeItem(at: install.configURL(for: "iq3_xxs"))
        try FileManager.default.removeItem(at: install.configURL(for: "ud-q4_k_xl"))
        #expect(SettingsStore(defaults: defaults).settings.model == "q2_0")
    }
}
