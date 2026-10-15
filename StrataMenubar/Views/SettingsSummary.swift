import Foundation

/// The saved values as the menu lists them and as the settings window describes a running server. The five main
/// values are always there; a tuning value only when it is not left to the engine or to setup, so that what has been
/// changed stands out.
enum SettingsSummary {
    struct Row: Identifiable, Equatable {
        var label: String
        var value: String
        /// Left to the engine or to setup: hidden unless something makes it worth showing.
        var isDefault: Bool

        var id: String { label }
    }

    static func rows(for settings: StrataSettings, modelName: String? = nil) -> [Row] {
        [
            Row(label: "Model", value: modelName ?? settings.model, isDefault: false),
            Row(label: "Expert cache", value: settings.autoExpertCache ? "Auto" : "\(RunConfig.gigabytes(settings.expertCacheGB)) GB", isDefault: false),
            Row(label: "Keep free for macOS", value: keepFree(settings), isDefault: !settings.autoExpertCache || settings.keepFreeGB == nil),
            Row(label: "Context", value: String(settings.maxContext), isDefault: false),
            Row(label: "Port", value: String(settings.port), isDefault: false),
            Row(label: "Idle unload", value: idleUnload(settings.idleUnloadMinutes), isDefault: false),
            Row(label: "Verify window", value: settings.specWindow.map(String.init) ?? "As set up", isDefault: settings.specWindow == nil),
            Row(label: "Prompt chunk", value: settings.promptChunk.map(String.init) ?? "Auto", isDefault: settings.promptChunk == nil),
            Row(label: "Fit max_tokens", value: settings.fitMaxTokens ? "on" : "off", isDefault: !settings.fitMaxTokens),
        ]
    }

    /// One line for "Started with": the rows that are not defaults, in the menu's order.
    static func describe(_ settings: StrataSettings, modelName: String? = nil) -> String {
        rows(for: settings, modelName: modelName)
            .filter { !$0.isDefault }
            .map { "\($0.label.lowercased()) \($0.value)" }
            .joined(separator: ", ")
    }

    static func idleUnload(_ minutes: Int) -> String {
        minutes > 0 ? "\(minutes) min" : "Never"
    }

    private static func keepFree(_ settings: StrataSettings) -> String {
        guard settings.autoExpertCache, let keepFreeGB = settings.keepFreeGB else { return "Engine default" }
        return "\(keepFreeGB) GB"
    }
}
