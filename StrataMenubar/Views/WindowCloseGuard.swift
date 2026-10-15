import AppKit
import SwiftUI

/// Asks before the hosting window closes on unsaved changes. It takes over the window's delegate only for
/// `windowShouldClose` and forwards every other delegate call to whatever delegate SwiftUI installed.
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
            let alert = NSAlert()
            alert.messageText = "Discard unsaved changes?"
            alert.informativeText = "The settings you changed have not been applied. Close the window anyway?"
            alert.addButton(withTitle: "Discard Changes")
            alert.addButton(withTitle: "Keep Editing")
            alert.beginSheetModal(for: sender) { response in
                guard response == .alertFirstButtonReturn else { return }
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

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let coordinator, window.delegate !== coordinator else { return }
            coordinator.original = window.delegate
            window.delegate = coordinator
        }
    }
}
