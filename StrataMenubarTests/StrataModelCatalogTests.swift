import Foundation
import Testing
@testable import StrataMenubar

struct StrataModelCatalogTests {
    private let packs = StrataModelCatalog.packs
    private let smallMac = MemoryBudget(physicalMemoryBytes: 32 << 30)
    private let bigMac = MemoryBudget(physicalMemoryBytes: 128 << 30)

    @Test func listsTheMacPacksInTheDocumentedOrder() {
        #expect(packs.map(\.name) == ["Q2_0", "IQ3_XXS", "IQ3_S", "UD-Q4_K_XL", "UD-Q5_K_XL", "UD-Q6_K_XL"])
        for pack in packs {
            #expect(pack.mappedFileGB > 0)
            #expect(pack.downloadGB > 0)
            #expect(pack.recommendedFromGB > 0)
            #expect(pack.expertsCopyGB > 0)
        }
        #expect(packs[0].needsAboutGB == 46)
        #expect(packs[4].needsAboutGB == nil)
        #expect(packs.map(\.shards) == [2, 2, 2, 4, 6, 6])
    }

    @Test func marksAPackAsInstalledWhenItsConfigExists() {
        let installed = [
            InstalledModel(tag: "q2_0", modelName: "qwen3.8-flash-next-q2_0", configURL: URL(filePath: "/x/strata-q2_0.json")),
            InstalledModel(tag: "unsloth-ud-q4_k_xl", modelName: "qwen3.8-flash-next-unsloth-ud-q4_k_xl", configURL: URL(filePath: "/x/strata-unsloth-ud-q4_k_xl.json")),
        ]
        #expect(packs[0].isInstalled(among: installed))
        #expect(packs[3].isInstalled(among: installed))
        #expect(!packs[1].isInstalled(among: installed))
    }

    /// Setup names the config, the model directory and the shards from the family: the Unsloth packs carry an
    /// `unsloth-` prefix and the family's own shard pattern.
    @Test func namesTagsDirectoriesAndShardsLikeSetup() {
        let iq3s = packs[2]
        #expect(iq3s.tag == "iq3_s")
        #expect(iq3s.directoryName == "IQ3_S")
        #expect(iq3s.shardNames == [
            "Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf",
            "Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf",
        ])
        let ud4 = packs[3]
        #expect(ud4.tag == "unsloth-ud-q4_k_xl")
        #expect(ud4.directoryName == "unsloth-UD-Q4_K_XL")
        #expect(ud4.shardNames.count == 4)
        #expect(ud4.shardNames[0] == "Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf")
        #expect(packs[5].shardNames.last == "Qwen3.8-Flash-Next-UD-Q6_K_XL-00006-of-00006.gguf")

        #expect(StrataModelCatalog.pack(forTag: "unsloth-ud-q4_k_xl")?.name == "UD-Q4_K_XL")
        #expect(StrataModelCatalog.pack(forTag: "q2_0")?.name == "Q2_0")
        #expect(StrataModelCatalog.pack(forTag: "ud-q4_k_xl") == nil)
    }

    /// The streaming rule is setup's: shard 1 plus 8 GB against three quarters of the memory (a 64 GB Mac also keeps
    /// 30% for macOS). A streaming Mac under 96 GB writes the experts' copy, so its disk estimate includes it.
    @Test func streamsAndEstimatesDiskLikeSetup() {
        for pack in packs {
            #expect(pack.streams(memory: smallMac), "\(pack.name) streams on 32 GiB")
        }
        #expect(!packs[2].streams(memory: bigMac))
        #expect(!packs[3].streams(memory: bigMac))
        #expect(packs[4].streams(memory: bigMac))

        #expect(approximately(packs[2].diskEstimateGB(memory: smallMac), 135.4))
        #expect(approximately(packs[2].diskEstimateGB(memory: bigMac), 85.1))
        #expect(approximately(packs[3].diskEstimateGB(memory: smallMac), 272.4))
        #expect(approximately(packs[4].diskEstimateGB(memory: bigMac), 263.7))
        #expect(approximately(packs[2].requiredFreeGB(memory: smallMac), 145.4))
    }

    @Test func plansTheSetupRunThroughTheCheckoutsInterpreter() throws {
        let install = try TestInstallation.make()
        defer { install.remove() }
        let log = URL(filePath: "/tmp/logs/setup.log")
        let plan = SetupPlan.make(installation: StrataInstallation(root: install.root), pack: StrataModelCatalog.packs[2], log: log)
        #expect(plan.executable == install.python)
        #expect(plan.arguments == [install.root.appending(path: "setup.py").path(percentEncoded: false), "--setup", "--model", "IQ3_S", "--no-start", "--vision", "no"])
        #expect(plan.workingDirectory == install.root)
        #expect(plan.environment["PYTHONUNBUFFERED"] == "1")
        #expect(plan.environment["PATH"] == ProcessInfo.processInfo.environment["PATH"])
        #expect(plan.standardOutputLog == log)
    }

    private func approximately(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.01
    }
}
