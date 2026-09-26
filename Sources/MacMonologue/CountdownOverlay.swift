import AppKit
import SwiftUI

/// The 3-2-1 before a take, big in the middle of the screen being recorded and
/// above every app — a take is often started by shortcut from inside the
/// presentation, with Mac-Monologue's window nowhere in sight. It is never in the
/// recording: the screen capture leaves out everything of this process.
///
/// Clicks pass through it, and it never takes focus from the app in front.
@MainActor
final class CountdownOverlay {
    private var panel: NSPanel?
    private let model = CountdownModel()

    /// `startsOnScreen`, in Touch Cut mode, tells live whether the take would
    /// open on the screen or on the head; nil in the other modes.
    func show(seconds: Int, on display: CGDirectDisplayID?, startsOnScreen: (() -> Bool)?) {
        model.seconds = seconds
        model.startsOnScreen = startsOnScreen
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { $0.displayID == display } ?? NSScreen.main
        if let frame = screen?.frame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 320, height: 320)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CountdownView(model: model))
        return panel
    }
}

@MainActor
final class CountdownModel: ObservableObject {
    @Published var seconds = 3
    @Published var startsOnScreen: (() -> Bool)?
}

struct CountdownView: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        VStack(spacing: 6) {
            Text("\(model.seconds)")
                .font(.system(size: 110, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: model.seconds)
            if let startsOnScreen = model.startsOnScreen {
                // The trackpad has no change notification worth wiring for three
                // seconds; ten looks a second are plenty to feel instant.
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let screen = startsOnScreen()
                    Label(screen ? "Starts on the screen" : "Starts on you",
                          systemImage: screen ? "rectangle.inset.bottomright.filled" : "person.fill")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 240, height: 240)
        .background(.ultraThinMaterial, in: Circle())
        .frame(width: 320, height: 320)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

#Preview("Countdown") { CountdownView(model: { let m = CountdownModel(); m.seconds = 3; return m }()) }
#Preview("Countdown · Touch Cut") {
    CountdownView(model: { let m = CountdownModel(); m.seconds = 2; m.startsOnScreen = { true }; return m }())
}
