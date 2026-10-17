import Testing
@testable import StrataMenubar

struct SetupOutputTests {
    @Test func readsStepsProgressAndFailuresAcrossReads() {
        var parser = SetupOutputParser()
        let first = parser.feed("=== Step 5: downloading Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S ===\n\r  shard-1.gguf: 1.23 / 41.80 GB (3%)\r  shard-1.gguf: 2.0")
        #expect(first == [
            .step(number: 5, title: "downloading Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S"),
            .shardProgress(name: "shard-1.gguf", haveBytes: 1_230_000_000, totalBytes: 41_800_000_000),
        ])
        let second = parser.feed("0 / 41.80 GB (5%)\n[ok] shard-2.gguf already downloaded\n=== Step 6: preparing the model for Strata ===\n[X]  a Strata engine is running\nstopped.\n")
        #expect(second == [
            .shardProgress(name: "shard-1.gguf", haveBytes: 2_000_000_000, totalBytes: 41_800_000_000),
            .alreadyDownloaded(name: "shard-2.gguf"),
            .step(number: 6, title: "preparing the model for Strata"),
            .failure(message: "a Strata engine is running"),
            .stopped,
        ])
        #expect(parser.feed("Collecting pip packages\n\n").isEmpty)
        // A finished progress line shows at once; a cut one waits for its rest.
        #expect(parser.feed("\r  shard-1.gguf: 3.00 / 41.80 GB (7%)") == [.shardProgress(name: "shard-1.gguf", haveBytes: 3_000_000_000, totalBytes: 41_800_000_000)])
        #expect(parser.feed("\r  shard-1.gguf: 3.50 / 41.80 GB (8").isEmpty)
        #expect(parser.feed("%)") == [.shardProgress(name: "shard-1.gguf", haveBytes: 3_500_000_000, totalBytes: 41_800_000_000)])
        #expect(parser.feed("[X]  SHA mismatch").isEmpty)
        #expect(parser.finish() == [.failure(message: "SHA mismatch")])
        #expect(parser.finish().isEmpty)
    }
}
