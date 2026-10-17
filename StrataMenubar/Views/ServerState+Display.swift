import SwiftUI

extension ServerState {
    /// The icon is at full strength only while this app's own server runs; health, idle unload and failures stay in the status line.
    var menuBarIcon: ImageResource {
        switch self {
        case .running: .layerGroup
        case .stopped, .starting, .stopping, .external, .failed: .layerGroupDimmed
        }
    }

    var statusText: String {
        switch self {
        case .stopped:
            "Stopped"
        case .starting(let info):
            switch info.phase {
            case .preparing: "Starting on port \(info.port): preparing \(info.model)…"
            case .loading(let pid): "Starting on port \(info.port) (PID \(pid))…"
            }
        case .running(let info):
            "Running on port \(info.port): \(info.model ?? "unknown model"), context \(info.maxContext.map(String.init) ?? "?")"
                + (info.isIdleUnloaded ? " (model unloaded after idle; loads on the next request)" : info.health.suffix)
        case .stopping:
            "Stopping…"
        case .external(let info):
            "External Strata on port \(info.port): \(info.model ?? "unknown model")\(info.loaded ? "" : " (loading)")"
        case .failed(let message):
            "Error: \(message)"
        }
    }
}

private extension HealthStatus {
    var suffix: String {
        switch self {
        case .ok: ""
        case .notLoaded: " — health check: model not loaded"
        case .unreachable: " — health check: no answer"
        case .other(let detail): " — health check: \(detail)"
        }
    }
}
