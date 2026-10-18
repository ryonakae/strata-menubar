import AppKit
import SwiftUI

/// SwiftUI's Settings window has no `.resizable` style, and `.windowResizability` alone does not add it, so the
/// hosting window gets it once the view is in a window. Its size limits still come from the content's frame.
struct ResizableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ResizingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ResizingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.styleMask.insert(.resizable)
        }
    }
}
