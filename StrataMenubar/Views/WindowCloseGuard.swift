import AppKit
import SwiftUI

/// Whether the settings window holds an unapplied draft, shared with the app delegate so that quitting can ask too.
@MainActor
@Observable
final class SettingsDraftState {
    var isDirty = false
}

/// The "Discard Changes / Keep Editing" alert; Keep Editing answers both Return and Escape, discarding is destructive.
enum UnappliedChangesAlert {
    static func make(informativeText: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Discard unapplied settings changes?"
        alert.informativeText = informativeText
        let keep = alert.addButton(withTitle: "Keep Editing")
        keep.keyEquivalent = "\u{1b}"
        let discard = alert.addButton(withTitle: "Discard Changes")
        discard.hasDestructiveAction = true
        return alert
    }

    static let discardResponse = NSApplication.ModalResponse.alertSecondButtonReturn
}

/// Asks before the hosting window closes on unsaved changes. It takes over the window's delegate only for
/// `windowShouldClose` and forwards every other delegate call to whatever delegate SwiftUI installed; the original
/// delegate is put back when the view leaves the window.
struct WindowCloseGuard: NSViewRepresentable {
    var isDirty: Bool
    var discard: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = GuardView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isDirty = isDirty
        context.coordinator.discard = discard
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        var isDirty = false
        var discard: () -> Void = {}
        nonisolated(unsafe) weak var original: NSWindowDelegate?

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard isDirty else {
                return original?.windowShouldClose?(sender) ?? true
            }
            let alert = UnappliedChangesAlert.make(informativeText: "The settings you changed have not been applied. Close the window anyway?")
            alert.beginSheetModal(for: sender) { response in
                guard response == UnappliedChangesAlert.discardResponse else { return }
                self.isDirty = false
                self.discard()
                sender.close()
            }
            return false
        }

        nonisolated override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
        }

        nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
            original
        }
    }

    final class GuardView: NSView {
        var coordinator: Coordinator?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil, let window, let coordinator, window.delegate === coordinator {
                window.delegate = coordinator.original
                coordinator.original = nil
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let coordinator, window.delegate !== coordinator else { return }
            coordinator.original = window.delegate
            window.delegate = coordinator
        }
    }
}
