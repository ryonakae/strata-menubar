import Foundation
import Testing
@testable import StrataMenubar

struct StrataSettingsTests {
    private let memory = MemoryBudget(physicalMemoryBytes: 32 << 30)

    private func errors(_ settings: StrataSettings) -> [SettingsIssue] {
        settings.validate(memory: memory).filter { $0.severity == .error }
    }

    private func warnings(_ settings: StrataSettings) -> [SettingsIssue] {
        settings.validate(memory: memory).filter { $0.severity == .warning }
    }

    @Test func defaultsMatchThePlanAndPassValidation() {
        let settings = StrataSettings.default
        #expect(settings.strataDirectory == "~/Dev/local/Strata")
        #expect(settings.model == "q2_0")
        #expect(settings.expertCacheGB == 5)
        #expect(settings.maxContext == 8192)
        #expect(settings.port == 8080)
        #expect(settings.validate(memory: memory).isEmpty)
    }

    @Test func expandsTheTildeInTheStrataDirectory() {
        #expect(StrataSettings.default.strataDirectoryURL.path(percentEncoded: false) == NSHomeDirectory() + "/Dev/local/Strata")
    }

    @Test func derivesTheCacheRangeAndWarningFromPhysicalMemory() {
        #expect(memory.physicalMemoryGiB == 32)
        #expect(memory.cacheRange == 1...32)
        #expect(memory.cacheWarningAboveGB == 16)
        let odd = MemoryBudget(physicalMemoryBytes: 24 << 30)
        #expect(odd.cacheWarningAboveGB == 12)
        #expect(MemoryBudget(physicalMemoryBytes: 1).cacheRange == 1...1)
    }

    @Test(arguments: [0.0, -1.0, Double.nan, Double.infinity])
    func rejectsANonPositiveOrNonFiniteCache(_ gigabytes: Double) {
        var settings = StrataSettings.default
        settings.expertCacheGB = gigabytes
        #expect(errors(settings).count == 1)
    }

    @Test func warnsAboveHalfTheMemoryAndBelowTwoGigabytesWithoutRejecting() {
        var half = StrataSettings.default
        half.expertCacheGB = 16
        #expect(half.validate(memory: memory).isEmpty)

        var large = StrataSettings.default
        large.expertCacheGB = 17
        #expect(errors(large).isEmpty)
        #expect(warnings(large).count == 1)
        #expect(warnings(large)[0].message.contains("32 GiB"))

        var two = StrataSettings.default
        two.expertCacheGB = 2
        #expect(two.validate(memory: memory).isEmpty)

        var small = StrataSettings.default
        small.expertCacheGB = 1
        #expect(errors(small).isEmpty)
        #expect(warnings(small).count == 1)
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

    @Test func rejectsAnEmptyDirectoryOrModel() {
        var settings = StrataSettings.default
        settings.strataDirectory = "   "
        #expect(errors(settings).count == 1)

        var noModel = StrataSettings.default
        noModel.model = ""
        #expect(errors(noModel).count == 1)
    }

    @Test func contextStepsArePowersOfTwoAndSnapToTheNearestStep() {
        #expect(ContextSteps.values == [1024, 2048, 4096, 8192, 16384, 32768])
        #expect(ContextSteps.nearestIndex(to: 8192) == 3)
        #expect(ContextSteps.nearestIndex(to: 6144) == 2)
        #expect(ContextSteps.nearestIndex(to: 10000) == 3)
        #expect(ContextSteps.nearestIndex(to: 100_000) == 5)
        #expect(ContextSteps.nearestIndex(to: 1) == 0)
    }
}
