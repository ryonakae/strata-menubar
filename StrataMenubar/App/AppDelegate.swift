import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let manager = AppContainer.shared.serverManager
        switch manager.quitRequirement {
        case .none:
            return .terminateNow
        case .waitForStop:
            Task { @MainActor in
                await manager.waitForIdle()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .confirmStop(let description):
            guard confirmStopBeforeQuit(description) else { return .terminateCancel }
            Task { @MainActor in
                await manager.stop()
                let proceed = !manager.ownsProcess || confirmQuitLeavingProcess()
                sender.reply(toApplicationShouldTerminate: proceed)
            }
            return .terminateLater
        }
    }

    private func confirmStopBeforeQuit(_ description: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop the Strata server and quit?"
        alert.informativeText = "\(description). Quitting stops the server and its engine first; this can take a while."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmQuitLeavingProcess() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The server could not be stopped"
        alert.informativeText = "A process started by this app may still be running. Quit anyway and clean it up by hand, or cancel and retry."
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
