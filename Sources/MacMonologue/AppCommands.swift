import SwiftUI

/// The menu bar. A single-window app still needs one — it is where a Mac user
/// looks for the shortcuts, and where they find the recordings folder.
struct AppCommands: Commands {
    @ObservedObject var capture: CaptureController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Recording") { capture.newRecording() }
                .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Reveal Recordings in Finder") { capture.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu("Recording") {
            Button(recordTitle) { capture.toggleRecording() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(capture.state == .needsAccess
                          || capture.state == .unavailable
                          || capture.state == .finishing)

            Button("Finish") { capture.finishTake() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(capture.state != .recording && capture.state != .paused)

            Divider()

            Button("Discard…") { capture.requestDiscard() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(capture.state == .ready
                          || capture.state == .needsAccess
                          || capture.state == .unavailable)
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { capture.isShowingHelp = true }
                .keyboardShortcut("?", modifiers: [])
        }
    }

    private var recordTitle: String {
        switch capture.state {
        case .recording: "Pause"
        case .paused: "Resume"
        case .preview: capture.isPlaying ? "Pause Playback" : "Play"
        default: "Record"
        }
    }
}
