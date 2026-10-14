import Foundation
import Testing
@testable import StrataMenubar

@MainActor
struct SettingsStoreTests {
    @Test func startsFromTheDefaultsAndRoundTripsThroughUserDefaults() throws {
        let suite = "StrataMenubarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        #expect(store.settings == .default)

        var changed = StrataSettings.default
        changed.strataDirectory = "/tmp/Strata テスト dir"
        changed.model = "iq3_xxs"
        changed.expertCacheGB = 4.5
        changed.maxContext = 4096
        changed.port = 8090
        store.save(changed)

        #expect(store.settings == changed)
        #expect(SettingsStore(defaults: defaults).settings == changed)
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
