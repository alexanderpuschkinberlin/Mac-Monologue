import AVFoundation
import AVKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var capture: CaptureController

    var body: some View {
        VStack(spacing: 0) {
            header
            preview
            controls
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            capture.start()
            if SelfTest.isEnabled { SelfTest.run(capture: capture) }
        }
        .onDisappear { capture.stop() }
        .sheet(isPresented: $capture.isShowingHelp) { HelpSheet() }
        .confirmationDialog(
            "Discard this take?",
            isPresented: $capture.isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { capture.discardTake() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(capture.state == .preview
                 ? "The file moves to the Trash."
                 : "The take is not saved.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Picker("Mode", selection: $capture.mode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                Toggle("Mirror the recording", isOn: $capture.mirrorsRecording)
                    .toggleStyle(.checkbox)
                    .help(mirrorHelp)
            }

            HStack(alignment: .bottom, spacing: 16) {
                if capture.mode == .screenAndCamera {
                    labelled("Screen") {
                        Picker("Screen", selection: $capture.selectedDisplayID) {
                            ForEach(capture.displays) { display in
                                Text(display.displayName).tag(Optional(display.id))
                            }
                        }
                        .labelsHidden()
                    }
                }
                labelled(capture.state == .preview ? "Recording" : "Camera") {
                    Picker("Camera", selection: $capture.selectedCameraID) {
                        ForEach(capture.cameras) { option in
                            Text(option.displayName).tag(Optional(option.id))
                        }
                    }
                    .labelsHidden()
                }
                labelled("Microphone") {
                    Picker("Microphone", selection: $capture.selectedMicrophoneID) {
                        ForEach(capture.microphones) { option in
                            Text(option.displayName).tag(Optional(option.id))
                        }
                    }
                    .labelsHidden()
                }
            }

            if capture.mode == .screenAndCamera {
                labelled("Camera bubble") {
                    HStack(spacing: 12) {
                        CornerPickerView(corner: $capture.bubbleCorner)
                        Picker("Size", selection: $capture.bubbleSize) {
                            ForEach(BubbleSize.allCases, id: \.self) { size in
                                Text(size.label).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
        .disabled(capture.devicePickersLocked)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var mirrorHelp: String {
        switch capture.mode {
        case .camera:
            "The preview always looks like a mirror. Turn this on only if you want the "
                + "saved file mirrored too — text you hold up to the camera will then read backwards."
        case .screenAndCamera:
            "Mirrors the camera bubble in the saved file. The screen itself is never mirrored."
        }
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
            if capture.state == .preview, let player = capture.player {
                VideoPlayer(player: player)
            } else if capture.mode == .screenAndCamera {
                LivePreviewView(onAttach: capture.attachPreview)
                    .overlay { cornerHints }
            } else {
                CameraPreviewView(session: capture.session, generation: capture.sessionGeneration)
            }

            statusPill
                .padding(12)

            if !capture.formatSummary.isEmpty {
                formatPill
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }

            if capture.state == .needsAccess {
                accessOverlay
            } else if capture.mode == .screenAndCamera, capture.state != .preview,
                      capture.screenAccess == .denied || capture.screenAccess == .needsRelaunch {
                screenAccessOverlay
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

    /// Before a take, the other three corners are outlined, so choosing one is a
    /// deliberate look at where the bubble would cover the slide. They disappear
    /// once recording starts: the corner is fixed for the whole take.
    @ViewBuilder
    private var cornerHints: some View {
        if capture.state == .ready, capture.canvasSize.width > 0 {
            GeometryReader { geometry in
                let video = AVMakeRect(aspectRatio: capture.canvasSize,
                                       insideRect: CGRect(origin: .zero, size: geometry.size))
                ForEach(BubbleCorner.allCases, id: \.self) { corner in
                    let frame = BubbleLayout(corner: corner, size: capture.bubbleSize)
                        .normalizedFrame(canvasWidth: Int(capture.canvasSize.width),
                                         canvasHeight: Int(capture.canvasSize.height))
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: corner == capture.bubbleCorner ? 2 : 1.5,
                                                         dash: corner == capture.bubbleCorner ? [] : [5, 4]))
                        .foregroundStyle(corner == capture.bubbleCorner
                                         ? Color.accentColor : Color.white.opacity(0.55))
                        .frame(width: frame.width * video.width, height: frame.height * video.height)
                        .position(x: video.minX + frame.midX * video.width,
                                  y: video.minY + frame.midY * video.height)
                        .onTapGesture { capture.bubbleCorner = corner }
                }
            }
        }
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

    private var screenAccessOverlay: some View {
        VStack(spacing: 12) {
            Text("Mac-Monologue needs permission to record your screen.")
                .font(.headline)
            Text(capture.screenAccess == .needsRelaunch
                 ? "Permission is on. macOS only applies it after Mac-Monologue restarts."
                 : "Switch on Mac-Monologue under Screen & System Audio Recording, "
                   + "then restart the app — macOS only applies it after a restart.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            HStack(spacing: 12) {
                if capture.screenAccess != .needsRelaunch {
                    Button("Open System Settings…") { capture.openScreenRecordingSettings() }
                }
                Button("Restart Mac-Monologue") { capture.relaunch() }
                    .keyboardShortcut(.defaultAction)
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
            .disabled(capture.state == .finishing
                      || (capture.state == .ready && !capture.canRecord)
                      || capture.state == .needsAccess
                      || capture.state == .unavailable)

            if capture.state == .recording || capture.state == .paused {
                Button("Finish") { capture.finishTake() }
            }

            Text(Self.timecode(capture.elapsed))
                .font(.system(.title3, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(capture.state == .recording ? .primary : .secondary)

            Spacer()

            // The microphone only: that is what a person can do something about.
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

                Button("New recording") { capture.newRecording() }

                Button("Reveal in Finder") { capture.revealInFinder() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var recordButtonTitle: String {
        switch capture.state {
        case .recording: "Pause"
        case .paused: "Resume"
        case .preview: capture.isPlaying ? "Pause" : "Play"
        default: "Record"
        }
    }

    private var recordButtonIcon: String {
        switch capture.state {
        case .recording: "pause.circle"
        case .paused: "record.circle"
        case .preview: capture.isPlaying ? "pause.circle" : "play.circle"
        default: "record.circle"
        }
    }

    static func timecode(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
