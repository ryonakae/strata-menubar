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
        #expect(settings.strataDirectory == "~/Strata")
        #expect(settings.model == "q2_0")
        #expect(settings.autoExpertCache)
        #expect(settings.expertCacheGB == 5)
        #expect(settings.keepFreeGB == nil)
        #expect(settings.maxContext == 8192)
        #expect(settings.port == 8080)
        #expect(settings.idleUnloadMinutes == 0)
        #expect(settings.specWindow == nil)
        #expect(settings.promptChunk == nil)
        #expect(!settings.fitMaxTokens)
        #expect(settings.validate(memory: memory).isEmpty)
    }

    /// A fixed cache, as every settings test below that checks the cache value needs one.
    private var fixed: StrataSettings {
        var settings = StrataSettings.default
        settings.autoExpertCache = false
        return settings
    }

    @Test func expandsTheTildeInTheStrataDirectory() {
        #expect(StrataSettings.default.strataDirectoryURL.path(percentEncoded: false) == NSHomeDirectory() + "/Strata")
    }

    @Test func derivesTheCacheRangeAndWarningFromPhysicalMemory() {
        #expect(memory.physicalMemoryGiB == 32)
        #expect(memory.cacheRange == 1...32)
        #expect(memory.cacheWarningAboveGB == 16)
        let even = MemoryBudget(physicalMemoryBytes: 24 << 30)
        #expect(even.cacheWarningAboveGB == 12)
        let odd = MemoryBudget(physicalMemoryBytes: 3 << 30)
        #expect(odd.cacheWarningAboveGB == 2)
        #expect(MemoryBudget(physicalMemoryBytes: 1).cacheRange == 1...1)
    }

    @Test(arguments: [0.0, -1.0, Double.nan, Double.infinity])
    func rejectsANonPositiveOrNonFiniteFixedCache(_ gigabytes: Double) {
        var settings = fixed
        settings.expertCacheGB = gigabytes
        #expect(errors(settings).count == 1)

        var automatic = settings
        automatic.autoExpertCache = true
        #expect(automatic.validate(memory: memory).isEmpty)
    }

    @Test func warnsAboveHalfTheMemoryAndBelowTwoGigabytesWithoutRejecting() {
        var half = fixed
        half.expertCacheGB = 16
        #expect(half.validate(memory: memory).isEmpty)

        var large = fixed
        large.expertCacheGB = 17
        #expect(errors(large).isEmpty)
        #expect(warnings(large).count == 1)
        #expect(warnings(large)[0].message.contains("32 GiB"))

        var two = fixed
        two.expertCacheGB = 2
        #expect(two.validate(memory: memory).isEmpty)

        var small = fixed
        small.expertCacheGB = 1
        #expect(errors(small).isEmpty)
        #expect(warnings(small).count == 1)
    }

    @Test func checksTheKeptMemoryOnlyWithAnAutomaticCache() {
        var tooSmall = StrataSettings.default
        tooSmall.keepFreeGB = 0
        #expect(errors(tooSmall).count == 1)

        var tooLarge = StrataSettings.default
        tooLarge.keepFreeGB = 33
        #expect(errors(tooLarge).count == 1)

        var belowTheEngineFloor = StrataSettings.default
        belowTheEngineFloor.keepFreeGB = 6
        #expect(errors(belowTheEngineFloor).isEmpty)
        #expect(warnings(belowTheEngineFloor).count == 1)
        #expect(warnings(belowTheEngineFloor)[0].message.contains("93 MB"))

        var atTheFloor = StrataSettings.default
        atTheFloor.keepFreeGB = 7
        #expect(atTheFloor.validate(memory: memory).isEmpty)

        var ignoredWithAFixedCache = fixed
        ignoredWithAFixedCache.keepFreeGB = 0
        #expect(ignoredWithAFixedCache.validate(memory: memory).isEmpty)
    }

    @Test func engineDefaultsFollowTheMemoryAndTheStreamingChoice() {
        #expect(EngineDefaults.keepFreeGB(memory: memory) == 7)
        #expect(EngineDefaults.promptChunk(memory: memory, streaming: true) == 1024)
        #expect(EngineDefaults.promptChunk(memory: memory, streaming: false) == 2048)
        #expect(EngineDefaults.promptChunk(memory: memory, streaming: nil) == nil)

        let big = MemoryBudget(physicalMemoryBytes: 128 << 30)
        #expect(EngineDefaults.keepFreeGB(memory: big) == 20.6)
        #expect(EngineDefaults.promptChunk(memory: big, streaming: true) == 4096)
        #expect(EngineDefaults.promptChunk(memory: MemoryBudget(physicalMemoryBytes: 96 << 30), streaming: true) == 4096)
        #expect(EngineDefaults.promptChunk(memory: MemoryBudget(physicalMemoryBytes: (96 << 30) - 1), streaming: true) == 1024)
    }

    @Test func rejectsANegativeIdleUnload() {
        var negative = StrataSettings.default
        negative.idleUnloadMinutes = -1
        #expect(errors(negative).count == 1)

        var five = StrataSettings.default
        five.idleUnloadMinutes = 5
        #expect(five.validate(memory: memory).isEmpty)
    }

    @Test func checksTheSpecWindowAgainstTheEngineAndTheBaseConfig() {
        for outside in [1, 9] {
            var settings = StrataSettings.default
            settings.specWindow = outside
            #expect(errors(settings).count == 1)
        }

        var two = StrataSettings.default
        two.specWindow = 2
        #expect(two.validate(memory: memory).isEmpty)

        var five = StrataSettings.default
        five.specWindow = 5
        #expect(errors(five).isEmpty)
        #expect(warnings(five).count == 1)

        let noDraft = BaseConfigFacts(specWindow: 2, hasMTP: false, streaming: true)
        #expect(two.validate(memory: memory, base: noDraft).map(\.severity) == [.warning])
        #expect(two.validate(memory: memory, base: noDraft)[0].message.contains("--mtp"))
        #expect(StrataSettings.default.validate(memory: memory, base: noDraft).isEmpty)

        let draft = BaseConfigFacts(specWindow: 3, hasMTP: true, streaming: true)
        #expect(two.validate(memory: memory, base: draft).isEmpty)
    }

    @Test func checksThePromptChunkAgainstTheEngineAndThisMac() {
        for outside in [0, 100, 8256] {
            var settings = StrataSettings.default
            settings.promptChunk = outside
            #expect(errors(settings).count == 1, "\(outside)")
        }

        var chunk = StrataSettings.default
        chunk.promptChunk = 2048
        #expect(chunk.validate(memory: memory).isEmpty)

        let streaming = BaseConfigFacts(specWindow: 2, hasMTP: false, streaming: true)
        #expect(chunk.validate(memory: memory, base: streaming).map(\.severity) == [.warning])
        #expect(chunk.validate(memory: memory, base: streaming)[0].message.contains("4.3 GB"))

        var atTheDefault = StrataSettings.default
        atTheDefault.promptChunk = 1024
        #expect(atTheDefault.validate(memory: memory, base: streaming).isEmpty)

        let resident = BaseConfigFacts(specWindow: 2, hasMTP: true, streaming: false)
        var large = StrataSettings.default
        large.promptChunk = 4096
        #expect(large.validate(memory: memory, base: resident).isEmpty)
    }

    @Test func effectiveSettingsIgnoreTheValuesTheModeLeavesUnused() {
        var automatic = StrataSettings.default
        automatic.expertCacheGB = 8
        #expect(automatic.effective == StrataSettings.default.effective)
        #expect(automatic != StrataSettings.default)

        var keeping = fixed
        keeping.keepFreeGB = 9
        #expect(keeping.effective == fixed.effective)

        var keepingAutomatic = StrataSettings.default
        keepingAutomatic.keepFreeGB = 9
        #expect(keepingAutomatic.effective != StrataSettings.default.effective)

        var larger = fixed
        larger.expertCacheGB = 8
        #expect(larger.effective != fixed.effective)
        #expect(fixed.effective != StrataSettings.default.effective)
    }

    @Test func stepsForIdleUnloadPromptChunkAndSpecWindow() {
        #expect(IdleUnloadSteps.minutes == [0, 5, 10, 15, 30, 60, 120])
        #expect(PromptChunkSteps.values == [1024, 2048, 4096, 8192])
        #expect(SpecWindow.range == 2...8)
    }

    @Test(arguments: [0, -1])
    func rejectsANonPositiveContext(_ context: Int) {
        var settings = StrataSettings.default
        settings.maxContext = context
        #expect(errors(settings).count == 1)
    }

    @Test func warnsAboutContextsAboveTheMeasured32KOnly() {
        var beyond = StrataSettings.default
        beyond.maxContext = 65536
        #expect(errors(beyond).isEmpty)
        #expect(warnings(beyond).count == 1)
        #expect(warnings(beyond)[0].message.contains("32K"))

        var measured = StrataSettings.default
        measured.maxContext = 32768
        #expect(measured.validate(memory: memory).isEmpty)

        var small = StrataSettings.default
        small.maxContext = 1024
        #expect(small.validate(memory: memory).isEmpty)
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
        #expect(ContextSteps.values == [1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144])
        #expect(ContextSteps.nearestIndex(to: 8192) == 3)
        #expect(ContextSteps.nearestIndex(to: 6144) == 2)
        #expect(ContextSteps.nearestIndex(to: 10000) == 3)
        #expect(ContextSteps.nearestIndex(to: 100_000) == 7)
        #expect(ContextSteps.nearestIndex(to: 1_000_000) == 8)
        #expect(ContextSteps.nearestIndex(to: 1) == 0)
    }
}
