import AppKit
import SwiftUI

/// What sits in the menu bar: always there, so the recorder can be reached with
/// its window minimised and PowerPoint in front — and a red dot with the running
/// time while recording, the one sign that a take is live.
struct MenuBarLabel: View {
    @ObservedObject var capture: CaptureController

    var body: some View {
        switch capture.state {
        case .recording:
            HStack(spacing: 4) {
                Image(nsImage: Self.dot(.systemRed))
                Text(ContentView.timecode(capture.elapsed)).monospacedDigit()
            }
        case .paused:
            HStack(spacing: 4) {
                Image(nsImage: Self.dot(.systemYellow))
                Text(ContentView.timecode(capture.elapsed)).monospacedDigit()
            }
        default:
            Image(systemName: "record.circle")
        }
    }

    /// Coloured, not a template image: a template would be drawn monochrome and
    /// the red would be lost.
    private static func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

struct MenuBarMenu: View {
    @ObservedObject var capture: CaptureController
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var subtitles: SubtitleCenter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(statusLine)

        if let job = subtitles.job, job.state == .running {
            Text("Creating subtitles · \(job.progress.percent)%")
        }

        if let newest = updates.availableReleases.first?.version {
            Button("Update Available: \(newest.description)…") {
                updates.checkNow(userInitiated: true)
            }
        }

        Divider()

        Button(recordTitle) { capture.toggleRecording() }
            .disabled(capture.state == .finishing
                      || (capture.state == .ready && !capture.canRecord)
                      || capture.state == .needsAccess
                      || capture.state == .unavailable
                      || capture.state == .preview)

        Button("Finish" + hint(capture.finishShortcut)) { capture.finishTake() }
            .disabled(capture.state != .recording && capture.state != .paused)

        Button("Discard…") {
            showWindow()
            capture.requestDiscard()
        }
        .disabled(capture.state != .recording && capture.state != .paused && capture.state != .preview)

        Divider()

        Button("Show Mac-Monologue") { showWindow() }
        Button("Reveal Recordings in Finder") { capture.revealInFinder() }
        Button("Check for Updates…") { updates.checkNow(userInitiated: true) }
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }

        Divider()

        Button("Quit Mac-Monologue") { NSApp.terminate(nil) }
    }

    private var statusLine: String {
        switch capture.state {
        case .recording: "Recording · \(ContentView.timecode(capture.elapsed))"
        case .paused: "Paused · \(ContentView.timecode(capture.elapsed))"
        case .finishing: "Finishing…"
        case .preview: "Take saved"
        case .ready: "Ready · \(capture.mode.label)"
        case .needsAccess: "Camera access needed"
        case .unavailable: "No camera"
        }
    }

    private var recordTitle: String {
        let title = switch capture.state {
        case .recording: "Pause"
        case .paused: "Resume"
        default: "Record"
        }
        return title + hint(capture.toggleShortcut)
    }

    private func hint(_ shortcut: Shortcut) -> String { "  (\(shortcut.displayString))" }

    private func showWindow() {
        openWindow(id: "main")
        capture.showMainWindow()
    }
}
