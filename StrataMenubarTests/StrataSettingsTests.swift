import Foundation
import Testing
@testable import StrataMenubar

struct StrataSettingsTests {
    private func errors(_ settings: StrataSettings) -> [SettingsIssue] {
        settings.validate().filter { $0.severity == .error }
    }

    private func warnings(_ settings: StrataSettings) -> [SettingsIssue] {
        settings.validate().filter { $0.severity == .warning }
    }

    @Test func defaultsMatchThePlanAndPassValidation() {
        let settings = StrataSettings.default
        #expect(settings.strataDirectory == "~/Dev/local/Strata")
        #expect(settings.expertCacheGB == 5)
        #expect(settings.maxContext == 8192)
        #expect(settings.port == 8080)
        #expect(settings.validate().isEmpty)
    }

    @Test func expandsTheTildeInTheStrataDirectory() {
        #expect(StrataSettings.default.strataDirectoryURL.path(percentEncoded: false) == NSHomeDirectory() + "/Dev/local/Strata")
    }

    @Test(arguments: [0.0, -1.0, Double.nan, Double.infinity])
    func rejectsANonPositiveOrNonFiniteCache(_ gigabytes: Double) {
        var settings = StrataSettings.default
        settings.expertCacheGB = gigabytes
        #expect(errors(settings).count == 1)
    }

    @Test func warnsAboutUntestedCacheSizesWithoutRejectingThem() {
        var small = StrataSettings.default
        small.expertCacheGB = 1
        #expect(errors(small).isEmpty)
        #expect(warnings(small).count == 1)

        var large = StrataSettings.default
        large.expertCacheGB = 20
        #expect(errors(large).isEmpty)
        #expect(warnings(large).count == 1)
    }

    @Test(arguments: [0, -1])
    func rejectsANonPositiveContext(_ context: Int) {
        var settings = StrataSettings.default
        settings.maxContext = context
        #expect(errors(settings).count == 1)
    }

    @Test func warnsAboutContextsThatDifferFromTheTestedOne() {
        var large = StrataSettings.default
        large.maxContext = 16384
        #expect(errors(large).isEmpty)
        #expect(warnings(large).count == 1)

        var small = StrataSettings.default
        small.maxContext = 1024
        #expect(errors(small).isEmpty)
        #expect(warnings(small).count == 1)
    }

    @Test(arguments: [0, 80, 1023, 65536])
    func rejectsPrivilegedOrImpossiblePorts(_ port: Int) {
        var settings = StrataSettings.default
        settings.port = port
        #expect(errors(settings).count == 1)
    }

    @Test func rejectsAnEmptyDirectory() {
        var settings = StrataSettings.default
        settings.strataDirectory = "   "
        #expect(errors(settings).count == 1)
    }
}
