import Foundation

enum ProcessExit: Equatable, Sendable, CustomStringConvertible {
    case exited(Int32)
    case signaled(Int32)

    var description: String {
        switch self {
        case .exited(let status): "exit status \(status)"
        case .signaled(let signal): "killed by signal \(signal)"
        }
    }
}

/// A process this app started as the leader of its own process group. The group is the ownership boundary:
/// everything in it (the server and the engine it spawns) may be signalled, nothing outside it ever is.
protocol OwnedProcess: AnyObject, Sendable {
    var pid: pid_t { get }
    var processGroup: pid_t { get }

    /// Waits for the direct child to end and be reaped; safe to call from several places.
    func waitForExit() async -> ProcessExit
    func exitIfFinished() -> ProcessExit?
    func signal(_ signal: Int32) throws
    func signalGroup(_ signal: Int32) throws
    /// Whether any member of the group is still alive.
    func isGroupAlive() -> Bool
}

protocol ProcessLaunching: Sendable {
    func launch(_ plan: LaunchPlan) throws -> any OwnedProcess
}
