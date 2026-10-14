import Foundation
import Testing
@testable import StrataMenubar

struct StrataModelCatalogTests {
    @Test func listsTheMacPacksInTheDocumentedOrder() {
        #expect(StrataModelCatalog.packs.map(\.name) == ["Q2_0", "IQ3_XXS", "IQ3_S", "UD-Q4_K_XL", "UD-Q5_K_XL", "UD-Q6_K_XL"])
        for pack in StrataModelCatalog.packs {
            #expect(pack.mappedFileGB > 0)
            #expect(pack.downloadGB > 0)
            #expect(pack.recommendedFromGB > 0)
        }
        #expect(StrataModelCatalog.packs[0].needsAboutGB == 46)
        #expect(StrataModelCatalog.packs[4].needsAboutGB == nil)
    }

    @Test func marksAPackAsInstalledWhenItsConfigExists() {
        let installed = [
            InstalledModel(tag: "q2_0", modelName: "qwen3.8-flash-next-q2_0", configURL: URL(filePath: "/x/strata-q2_0.json")),
            InstalledModel(tag: "ud-q4_k_xl", modelName: "qwen3.8-flash-next-ud-q4_k_xl", configURL: URL(filePath: "/x/strata-ud-q4_k_xl.json")),
        ]
        #expect(StrataModelCatalog.packs[0].isInstalled(among: installed))
        #expect(StrataModelCatalog.packs[3].isInstalled(among: installed))
        #expect(!StrataModelCatalog.packs[1].isInstalled(among: installed))
        #expect(StrataModelCatalog.packs[3].tag == "ud-q4_k_xl")
    }

    @Test func buildsTheSetupCommandWithAQuotedDirectory() {
        let command = SetupCommand.make(strataDirectory: "/Users/x/Dev local/Str\"ata", model: "IQ3_XXS")
        #expect(command == "cd \"/Users/x/Dev local/Str\\\"ata\" && ./setup.sh --setup --model IQ3_XXS --no-start")
        #expect(SetupCommand.make(strataDirectory: "~/Dev/local/Strata", model: "Q2_0") == "cd \"\(NSHomeDirectory())/Dev/local/Strata\" && ./setup.sh --setup --model Q2_0 --no-start")
    }
}
