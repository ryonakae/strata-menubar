import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Only a question: a quit that goes through takes the draft with the process, and a cancelled one keeps it.
        if AppContainer.shared.settingsDraft.isDirty, !confirmDiscardingSettingsDraft() {
            return .terminateCancel
        }
        let manager = AppContainer.shared.serverManager
        switch manager.quitRequirement {
        case .none:
            return .terminateNow
        case .confirmStop(let description):
            guard confirmStopBeforeQuit(description) else { return .terminateCancel }
        case .waitForStop:
            break
        }
        Task { @MainActor in
            sender.reply(toApplicationShouldTerminate: await settleBeforeQuit(manager))
        }
        return .terminateLater
    }

    /// Stops whatever the app owns and only then allows the quit. The requirement is re-read after every wait: a stop
    /// can fail and keep the process, and a restart can hand over a brand-new server while we were waiting.
    private func settleBeforeQuit(_ manager: ServerManager) async -> Bool {
        while true {
            switch manager.quitRequirement {
            case .none:
                return true
            case .waitForStop:
                await manager.waitForIdle()
            case .confirmStop:
                await manager.stop()
                if manager.ownsProcess {
                    return confirmQuitLeavingProcess()
                }
            }
        }
    }

    private func confirmDiscardingSettingsDraft() -> Bool {
        let alert = UnappliedChangesAlert.make(informativeText: "The settings window has changes that have not been applied. Quit anyway?")
        NSApp.activate()
        return alert.runModal() == UnappliedChangesAlert.discardResponse
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
