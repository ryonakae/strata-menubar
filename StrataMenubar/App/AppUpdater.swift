import Foundation
import Sparkle

/// Checks for and installs app updates only when asked. Installing quits through `AppDelegate`, so a server or setup
/// the app started is stopped only after the usual confirmation.
@MainActor
@Observable
final class AppUpdater {
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial]) { [weak self] _, _ in
            // The KVO callback is not isolated; the value is read again on the main actor, where Sparkle keeps it.
            Task { @MainActor in
                guard let self else { return }
                self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
