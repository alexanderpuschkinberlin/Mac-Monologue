import AVFoundation
import SwiftUI

struct ContentView: View {
    @StateObject private var capture = CaptureController()

    var body: some View {
        VStack(spacing: 0) {
            devicePickers
            preview
            controls
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            capture.start()
            if SelfTest.isEnabled { SelfTest.run(capture: capture) }
        }
        .onDisappear { capture.stop() }
    }

    // MARK: - Pickers

    private var devicePickers: some View {
        HStack(alignment: .bottom, spacing: 16) {
            labelled("Camera") {
                Picker("Camera", selection: $capture.selectedCameraID) {
                    ForEach(capture.cameras) { option in
                        Text(option.displayName).tag(Optional(option.id))
                    }
                }
            }
            labelled("Microphone") {
                Picker("Microphone", selection: $capture.selectedMicrophoneID) {
                    ForEach(capture.microphones) { option in
                        Text(option.displayName).tag(Optional(option.id))
                    }
                }
            }
        }
        .labelsHidden()
        .disabled(capture.devicePickersLocked)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func labelled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            CameraPreviewView(session: capture.session)

            statusPill
                .padding(12)

            if !capture.formatSummary.isEmpty {
                formatPill
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }

            if capture.state == .needsAccess {
                accessOverlay
            }

            if let banner = capture.banner {
                Text(banner)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(capture.state.label)
                .font(.system(.caption, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var formatPill: some View {
        Text(capture.formatSummary)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var dotColor: Color {
        switch capture.state {
        case .ready, .preview: .green
        case .recording: .red
        case .paused: .yellow
        case .finishing: .orange
        case .needsAccess, .unavailable: .gray
        }
    }

    private var accessOverlay: some View {
        VStack(spacing: 12) {
            Text("Mac-Monologue needs access to your camera and microphone.")
                .multilineTextAlignment(.center)
            Button("Open Privacy & Security…") {
                // macOS only ever prompts once; after a denial the app has to
                // send the user to System Settings itself.
                let pane = capture.cameraAccessDenied ? "Privacy_Camera" : "Privacy_Microphone"
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: capture.toggleRecording) {
                Label(recordButtonTitle, systemImage: recordButtonIcon)
                    .frame(minWidth: 84)
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(capture.state == .needsAccess
                      || capture.state == .unavailable
                      || capture.state == .finishing)

            if capture.state == .recording || capture.state == .paused {
                Button("Finish") { capture.finishTake() }
                    .keyboardShortcut(.return, modifiers: .command)
            }

            Text(Self.timecode(capture.elapsed))
                .font(.system(.title3, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(capture.state == .recording ? .primary : .secondary)

            Spacer()

            if capture.hasAudio {
                LevelMeterView(
                    level: capture.audioLevel,
                    peak: capture.audioPeak,
                    isClipping: capture.isClipping
                )
                .frame(width: 180)
            }

            if capture.state == .preview, let url = capture.lastRecordingURL {
                Text(url.lastPathComponent)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("Reveal in Finder") { capture.revealInFinder() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var recordButtonTitle: String {
        switch capture.state {
        case .recording: "Pause"
        case .paused: "Resume"
        case .preview: "New recording"
        default: "Record"
        }
    }

    private var recordButtonIcon: String {
        switch capture.state {
        case .recording: "pause.circle"
        case .paused: "record.circle"
        case .preview: "arrow.clockwise.circle"
        default: "record.circle"
        }
    }

    static func timecode(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
