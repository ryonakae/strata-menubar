import AppKit
import SwiftUI

/// SwiftUI gives its Settings window no `.resizable` style and takes the style away again if it is added once, while
/// still setting the size limits from the content's frame. The style is therefore put back whenever it is removed.
struct ResizableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ResizingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ResizingView: NSView {
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.styleMask, options: [.initial]) { window, _ in
                // The callback runs where the style was changed, which for a window is the main thread.
                MainActor.assumeIsolated {
                    if !window.styleMask.contains(.resizable) {
                        window.styleMask.insert(.resizable)
                    }
                }
            }
        }
    }
}
