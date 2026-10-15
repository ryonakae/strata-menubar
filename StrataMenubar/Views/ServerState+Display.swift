import Foundation

extension ServerState {
    var symbolName: String {
        switch self {
        case .stopped: "stop.circle"
        case .starting, .stopping: "clock"
        case .running(let info):
            if info.isIdleUnloaded {
                "moon.circle"
            } else {
                info.health == .ok ? "checkmark.circle.fill" : "exclamationmark.circle"
            }
        case .external: "eye.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var statusText: String {
        switch self {
        case .stopped:
            "Stopped"
        case .starting(let info):
            "Starting on port \(info.port) (PID \(info.pid))…"
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
