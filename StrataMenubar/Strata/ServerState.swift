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
    var pid: pid_t
    var port: Int
    var since: Date
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

    init(state: ServerState, ownsProcess: Bool) {
        switch state {
        case .starting(let info):
            self = .confirmStop("The server (PID \(info.pid)) is still starting")
        case .running(let info):
            self = .confirmStop("The server (PID \(info.pid)) is running on port \(info.port)")
        case .stopping:
            self = .waitForStop
        case .failed where ownsProcess:
            self = .confirmStop("A server process started by this app may still be running")
        case .stopped, .external, .failed:
            self = .none
        }
    }
}
