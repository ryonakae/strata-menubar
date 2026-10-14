import Foundation

extension ServerState {
    var symbolName: String {
        switch self {
        case .stopped: "stop.circle"
        case .starting, .stopping: "clock"
        case .running: "checkmark.circle.fill"
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
        case .stopping:
            "Stopping…"
        case .external(let info):
            "External Strata on port \(info.port): \(info.model ?? "unknown model")\(info.loaded ? "" : " (loading)")"
        case .failed(let message):
            "Error: \(message)"
        }
    }
}
