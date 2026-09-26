import AVFoundation
import AVKit
import SwiftUI
import Translation

struct ContentView: View {
    @ObservedObject var capture: CaptureController

    var body: some View {
        VStack(spacing: 0) {
            header
            preview
            SubtitleProgressView(subtitles: capture.subtitles)
            controls
        }
        // Translation packs are fetched from here — macOS only offers that
        // through a view, and the main window is always there — except while the
        // welcome steps cover it: then they do it, so macOS's prompt is seen.
        .modifier(TranslationPreparation(subtitles: capture.subtitles, isActive: !capture.isShowingOnboarding))
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowAccessor { capture.setMainWindow($0) })
        .onAppear {
            // Before anything else: moving relaunches the app.
            if MoveToApplications.offerIfNeeded() { return }
            capture.start()
            if SelfTest.isEnabled { SelfTest.run(capture: capture) }
        }
        .onDisappear { capture.stop() }
        .sheet(isPresented: $capture.isShowingHelp) {
            HelpSheet(toggleShortcut: capture.toggleShortcut, finishShortcut: capture.finishShortcut)
        }
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
                        Text(mode.shortLabel).tag(mode)
                            .help(mode.cutsOnTouch
                                  ? "\(mode.label): the screen while a finger rests on the trackpad, you in full frame once you let go."
                                  : mode.label)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                if capture.mode.usesCamera, capture.framing != .unavailable {
                    VStack(alignment: .trailing, spacing: 2) {
                        Toggle("Keep me in frame", isOn: $capture.keepsMeInFrame)
                            .toggleStyle(.checkbox)
                            .help(framingHelp)
                        Text(capture.framing == .centerStage ? "Center Stage" : "Zooms in slightly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if capture.mode.usesCamera {
                    VStack(alignment: .trailing, spacing: 2) {
                        Toggle("Mirror the recording", isOn: $capture.mirrorsRecording)
                            .toggleStyle(.checkbox)
                            .help(mirrorHelp)
                        // On is rarely what anyone wants, and easy to forget:
                        // say what it does for as long as it is on.
                        if capture.mirrorsRecording {
                            Label("Text reads backwards in the saved file", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 16) {
                if capture.mode.recordsScreen {
                    labelled("Screen") {
                        Picker("Screen", selection: $capture.selectedDisplayID) {
                            ForEach(capture.displays) { display in
                                Text(display.displayName).tag(Optional(display.id))
                            }
                        }
                        .labelsHidden()
                    }
                }
                if capture.mode.usesCamera {
                    labelled(capture.state == .preview ? "Recording" : "Camera") {
                        Picker("Camera", selection: $capture.selectedCameraID) {
                            ForEach(capture.cameras) { option in
                                Text(option.displayName).tag(Optional(option.id))
                            }
                        }
                        .labelsHidden()
                    }
                }
                labelled("Microphone") {
                    Picker("Microphone", selection: $capture.selectedMicrophoneID) {
                        ForEach(capture.microphones) { option in
                            Text(option.displayName).tag(Optional(option.id))
                        }
                    }
                    .labelsHidden()
                }
                labelled("Quality") {
                    Picker("Quality", selection: $capture.videoQuality) {
                        ForEach(VideoQuality.allCases) { quality in
                            Text("\(quality.title) · \(quality.sizeLabel)").tag(quality)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("How sharp the video is, and how big the file gets. More in Settings.")
                }
            }

            if capture.mode.showsBubble {
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
        // On its own view: two sheets on one view do not both present reliably.
        .sheet(isPresented: $capture.isShowingOnboarding) {
            OnboardingView(capture: capture)
                .interactiveDismissDisabled()
        }
    }

    private var framingHelp: String {
        switch capture.framing {
        case .centerStage:
            "Uses this camera's Center Stage: it follows you as you move, at full sharpness. "
                + "You can also switch it in Control Center."
        case .software, .unavailable:
            "Follows your face by zooming in a little and moving with you. "
                + "The picture gets slightly softer, since part of it is cropped away."
        }
    }

    private var mirrorHelp: String {
        switch capture.mode {
        case .camera:
            "The preview always looks like a mirror. Turn this on only if you want the "
                + "saved file mirrored too — text you hold up to the camera will then read backwards."
        case .screenAndCamera:
            "Mirrors the camera bubble in the saved file. The screen itself is never mirrored."
        case .screenAndCameraTouchCut:
            "Mirrors the camera — bubble and full picture — in the saved file. The screen itself is never mirrored."
        case .screen:
            "The screen is never mirrored."
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
            } else if capture.mode.recordsScreen {
                LivePreviewView(onAttach: capture.attachPreview)
                    .overlay { cornerHints }
            } else if capture.followsFaceInSoftware {
                // The crop happens in the compositor; the preview layer would
                // show the whole, uncropped camera.
                LivePreviewView(onAttach: capture.attachPreview)
            } else {
                CameraPreviewView(session: capture.session, generation: capture.sessionGeneration,
                                  rotationAngle: capture.cameraRotationAngle)
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
            } else if capture.mode.recordsScreen, capture.state != .preview,
                      capture.screenAccess == .denied || capture.screenAccess == .needsRelaunch {
                screenAccessOverlay
            }

            if capture.cameraIsSilent {
                silentCameraHint
            } else if let banner = capture.banner {
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
        if capture.mode.showsBubble, capture.state == .ready, capture.canvasSize.width > 0 {
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
            Text(capture.countdown.map { "Starting in \($0)" } ?? capture.state.label)
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

    private var silentCameraHint: some View {
        HStack(spacing: 12) {
            Text("The camera isn't sending a picture. If it's your iPhone, wake it and keep it nearby.")
                .font(.callout)
            if let alternative = capture.alternativeCamera {
                Button("Use \(alternative.name)") { capture.useAlternativeCamera() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
            .keyboardShortcut(capture.countdown != nil ? .cancelAction : nil)
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

            if capture.mode.recordsScreen, capture.state != .preview {
                // Two sources, one fader between them — live during a take.
                AudioCrossfaderView(
                    balance: $capture.audioBalance,
                    ducksSystemAudio: $capture.ducksSystemAudio,
                    hasMicrophone: capture.hasAudio,
                    voiceLevel: capture.audioLevel, voicePeak: capture.audioPeak,
                    voiceClipping: capture.isClipping,
                    systemLevel: capture.systemAudioLevel, systemPeak: capture.systemAudioPeak
                )
            } else if capture.hasAudio {
                // The microphone only: that is what a person can do something about.
                LevelMeterView(
                    level: capture.audioLevel,
                    peak: capture.audioPeak,
                    isClipping: capture.isClipping
                )
                .frame(width: 180)
            }

            if capture.state == .preview, let url = capture.lastRecordingURL {
                Text([url.lastPathComponent, Self.fileSize(of: url)].compactMap { $0 }.joined(separator: " · "))
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
        if capture.countdown != nil { return "Cancel" }
        return switch capture.state {
        case .recording: "Pause"
        case .paused: "Resume"
        case .preview: capture.isPlaying ? "Pause" : "Play"
        default: "Record"
        }
    }

    private var recordButtonIcon: String {
        if capture.countdown != nil { return "xmark.circle" }
        return switch capture.state {
        case .recording: "pause.circle"
        case .paused: "record.circle"
        case .preview: capture.isPlaying ? "pause.circle" : "play.circle"
        default: "record.circle"
        }
    }

    /// As Finder shows it, so the number matches what the user sees there.
    static func fileSize(of url: URL) -> String? {
        guard let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func timecode(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Hands the translation pack the subtitle settings asked for to macOS. Only one
/// view at a time may be active, or macOS would be asked twice.
struct TranslationPreparation: ViewModifier {
    @ObservedObject var subtitles: SubtitleCenter
    var isActive = true

    func body(content: Content) -> some View {
        content.translationTask(isActive ? subtitles.translationToPrepare : nil) { session in
            do {
                try await Self.prepare(SessionHandle(session: session))
                subtitles.translationPrepared(nil)
            } catch {
                // The view went away mid-download — the welcome steps closing —
                // and the other view picks the same pack up again.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                subtitles.translationPrepared(error)
            }
        }
    }

    /// The session SwiftUI hands over is main-actor bound, and preparing it runs
    /// off the main actor. Nothing else touches it meanwhile: this task owns it.
    private struct SessionHandle: @unchecked Sendable {
        let session: TranslationSession
    }

    private nonisolated static func prepare(_ handle: SessionHandle) async throws {
        try await handle.session.prepareTranslation()
    }
}

#if DEBUG
private func window(_ capture: CaptureController) -> some View {
    ContentView(capture: capture).frame(width: 900, height: 640)
}

#Preview("Camera · ready") { window(.preview()) }
#Preview("Screen · ready") { window(.preview(mode: .screen)) }
#Preview("Screen + Camera · ready") { window(.preview(mode: .screenAndCamera)) }
#Preview("Screen & Head Touch Cut · ready") { window(.preview(mode: .screenAndCameraTouchCut)) }
#Preview("Screen + Camera · crossfader") {
    window(.preview(mode: .screenAndCamera, state: .recording, elapsed: 42, audioLevel: -14,
                    systemAudioLevel: -10, audioBalance: -0.4))
}
#Preview("Countdown") { window(.preview(mode: .screenAndCameraTouchCut, countdown: 2)) }
#Preview("Recording") { window(.preview(state: .recording, elapsed: 83, audioLevel: -9)) }
#Preview("Paused") { window(.preview(state: .paused, elapsed: 83)) }
#Preview("Finishing") { window(.preview(state: .finishing, elapsed: 83)) }
#Preview("Take saved · subtitles running") {
    window(.preview(state: .preview,
                    lastRecordingURL: URL(fileURLWithPath: "/Users/me/Movies/Monologue/Monologue-2026-09-24-171512.mp4"),
                    subtitleJob: SubtitleCenter.previewJob(step: .translating(.english, index: 0, count: 1), fraction: 0.4)))
}
#Preview("Keep me in frame · mirror on") { window(.preview(keepsMeInFrame: true, mirrorsRecording: true)) }
#Preview("Center Stage camera") { window(.preview(framing: .centerStage, keepsMeInFrame: true)) }
#Preview("Camera access needed") { window(.preview(state: .needsAccess)) }
#Preview("Screen access needed") { window(.preview(mode: .screenAndCamera, screenAccess: .denied)) }
#Preview("Screen access · restart") { window(.preview(mode: .screenAndCamera, screenAccess: .needsRelaunch)) }
#Preview("Camera silent") { window(.preview(cameraIsSilent: true)) }
#Preview("Banner") { window(.preview(mode: .screenAndCamera, banner: "The screen you chose last time is not connected. Pick another one.")) }
#Preview("No microphone · clipping") { window(.preview(hasAudio: false)) }
#Preview("Clipping") { window(.preview(state: .recording, elapsed: 12, audioLevel: -1, isClipping: true)) }
#Preview("Small window") { ContentView(capture: .preview(mode: .screenAndCamera)).frame(width: 820, height: 600) }
#endif
