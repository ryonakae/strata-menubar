import Foundation
import Observation

/// Owns the Strata server process this app starts and publishes its state to the UI.
@MainActor
@Observable
final class ServerManager {
    private(set) var state: ServerState = .stopped

    /// Whether a process group started by this app has not yet been confirmed gone.
    var ownsProcess: Bool { false }

    var quitRequirement: QuitRequirement {
        QuitRequirement(state: state, ownsProcess: ownsProcess)
    }

    func stop() async {}

    func waitForIdle() async {}
}
