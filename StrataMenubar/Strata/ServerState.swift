import Foundation

/// What the menu bar shows. Only `starting`, `running`, `stopping` and a failed stop refer to a process this app owns;
/// `external` is a Strata server somebody else started on the configured port and is never controlled from here.
enum ServerState: Equatable, Sendable {
    case stopped
    case starting(StartingInfo)
    case running(RunningInfo)
    case stopping
    case external(ExternalInfo)
    case failed(String)
}

struct StartingInfo: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Setup is preparing a downloaded model for its first start; there is no server process yet.
        case preparing
        case loading(pid: pid_t)
    }

    /// The tag being started, which a deletion has to leave alone.
    var model: String
    var phase: Phase
    var port: Int
    var since: Date

    var pid: pid_t? {
        if case .loading(let pid) = phase { return pid }
        return nil
    }
}

struct RunningInfo: Equatable, Sendable {
    var pid: pid_t
    /// The settings the server was started with; the saved settings may already differ.
    var settings: StrataSettings
    var model: String?
    var maxContext: Int?
    var since: Date
    var health: HealthStatus

    var port: Int { settings.port }

    /// An unloaded model is what idle unload does, not a failure, on a server that was started with it. The server
    /// does not say why the model is unloaded, so this also covers the reload a request has just triggered.
    var isIdleUnloaded: Bool { health == .notLoaded && settings.idleUnloadMinutes > 0 }
}

/// The last health check of a running server. A failing check is shown, never acted on: the process is still ours.
enum HealthStatus: Equatable, Sendable {
    case ok
    case notLoaded
    case unreachable
    case other(String)

    init(_ result: HealthProbeResult) {
        switch result {
        case .strata(let health): self = health.loaded ? .ok : .notLoaded
        case .unreachable: self = .unreachable
        case .occupied(let detail): self = .other(detail)
        }
    }
}

struct ExternalInfo: Equatable, Sendable {
    var port: Int
    var loaded: Bool
    var model: String?
    var maxContext: Int?
}

/// What quitting the app has to do before the process may exit.
enum QuitRequirement: Equatable, Sendable {
    case none
    case waitForStop
    case confirmStop(String)

    /// `download` describes a setup run this app owns, which has to be stopped before quitting as much as the server.
    init(state: ServerState, ownsProcess: Bool, download: String? = nil) {
        let server: QuitRequirement
        switch state {
        case .starting(let info):
            server = switch info.phase {
            case .preparing: .confirmStop("The model \(info.model) is being prepared for its first start")
            case .loading(let pid): .confirmStop("The server (PID \(pid)) is still starting")
            }
        case .running(let info):
            server = .confirmStop("The server (PID \(info.pid)) is running on port \(info.port)")
        case .stopping:
            server = .waitForStop
        case .failed where ownsProcess:
            server = .confirmStop("A server process started by this app may still be running")
        case .stopped, .external, .failed:
            server = .none
        }
        guard let download else {
            self = server
            return
        }
        // A stop that would only be waited for still gets the question, because of the download.
        if case .confirmStop(let text) = server {
            self = .confirmStop("\(text), and \(download.prefix(1).lowercased())\(download.dropFirst())")
        } else {
            self = .confirmStop(download)
        }
    }
}
