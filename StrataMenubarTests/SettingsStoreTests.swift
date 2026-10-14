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
        changed.expertCacheGB = 4.5
        changed.maxContext = 4096
        changed.port = 8090
        store.save(changed)

        #expect(store.settings == changed)
        #expect(SettingsStore(defaults: defaults).settings == changed)
    }
}
