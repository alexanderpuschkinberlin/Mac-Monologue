import AppKit
import SwiftUI

/// Hands the hosting `NSWindow` to whoever needs it — here, so the recorder can
/// minimise its own window when a screen take starts and bring it back after.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in onWindow(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
