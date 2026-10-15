import Foundation

/// What Strata's Metal engine chooses when a value is not set, computed the way the engine does so that the settings
/// can show it. The rules are from Strata's docs/MAC.md and the engine (arena_budget.h, window.cpp); a later Strata may
/// change them, which only makes the shown number stale, never the launch.
enum EngineDefaults {
    /// arena_budget.h keeps max(7 GB, 15% of the RAM) for macOS, in decimal gigabytes (kGB = 1e9).
    static let keepFreeFloorGB = 7.0

    static func keepFreeGB(memory: MemoryBudget) -> Double {
        let share = 0.15 * Double(memory.physicalMemoryBytes) / 1e9
        return (max(keepFreeFloorGB, share) * 10).rounded() / 10
    }

    /// window.cpp: a resident model reads prompts in chunks of 2048; a streaming one in 4096 from 96 GiB of RAM, else
    /// 1024. Without the streaming choice the engine decides by the model's size, which this app cannot see.
    static func promptChunk(memory: MemoryBudget, streaming: Bool?) -> Int? {
        guard let streaming else { return nil }
        guard streaming else { return 2048 }
        return memory.physicalMemoryBytes >= 96 << 30 ? 4096 : 1024
    }
}
