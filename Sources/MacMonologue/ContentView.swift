import AVFoundation
import AVKit
import SwiftUI
import Translation

/// The main window: the mode in the toolbar, the settings for that mode in the
/// sidebar, the preview - which is the recording - filling the rest, and the one
/// action of the moment in the bar below it.
struct ContentView: View {
    @ObservedObject var capture: CaptureController
    @State private var isShowingQuality = false
    @State private var dragStart: PersonLayout?

    var body: some View {
        NavigationSplitView {
            SidebarForm(capture: capture)
                .frame(minWidth: 270, idealWidth: 290)
                .navigationSplitViewColumnWidth(min: 270, ideal: 290, max: 360)
                // The settings are the point of the sidebar; hiding them helps nobody.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            preview
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        SubtitleProgressView(subtitles: capture.subtitles)
                        bottomBar
                    }
                }
        }
        // The window is the app: its name in the title bar would only take the
        // room the mode picker needs.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) { modePicker }
            ToolbarItemGroup(placement: .primaryAction) {
                statusPill
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("More settings")
            }
        }
        .navigationTitle("Mac-Monologue")
        // Translation packs are fetched from here — macOS only offers that
        // through a view, and the main window is always there — except while the
        // welcome steps cover it: then they do it, so macOS's prompt is seen.
        .modifier(TranslationPreparation(subtitles: capture.subtitles, isActive: !capture.isShowingOnboarding))
        .background(WindowAccessor { capture.setMainWindow($0) })
        .onAppear {
            // Before anything else: moving relaunches the app.
            if MoveToApplications.offerIfNeeded() { return }
            capture.start()
            if SelfTest.isEnabled { SelfTest.run(capture: capture) }
        }
        .onDisappear { capture.stop() }
        .sheet(isPresented: $capture.isShowingOnboarding) {
            OnboardingView(capture: capture)
                .interactiveDismissDisabled()
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
        .background {
            // Its own view: two sheets on one view do not both present reliably.
            Color.clear.sheet(isPresented: $capture.isShowingHelp) {
                HelpSheet(toggleShortcut: capture.toggleShortcut, finishShortcut: capture.finishShortcut)
            }
        }
    }

    // MARK: - Toolbar

    private var modePicker: some View {
        Picker("Mode", selection: $capture.mode) {
            ForEach(CaptureMode.allCases) { mode in
                Text(mode.shortLabel).tag(mode)
                    .help(mode.explanation)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(capture.devicePickersLocked)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.callout)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if let countdown = capture.countdown { return String(localized: "Starting in \(countdown)") }
        switch capture.state {
        case .recording: return String(localized: "Recording · \(Self.timecode(capture.elapsed))")
        case .paused: return String(localized: "Paused · \(Self.timecode(capture.elapsed))")
        default: return capture.state.label
        }
    }

    private var dotColor: Color {
        if capture.countdown != nil { return .orange }
        switch capture.state {
        case .ready, .preview: return .green
        case .recording: return .red
        case .paused: return .yellow
        case .finishing: return .orange
        case .needsAccess, .unavailable: return .gray
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            Color.black
            if capture.state == .preview, let player = capture.player {
                VideoPlayer(player: player)
            } else if capture.mode.recordsScreen {
                LivePreviewView(onAttach: capture.attachPreview)
                    .overlay { cornerHints }
                    .overlay { personHandle }
            } else if capture.followsFaceInSoftware {
                // The crop happens in the compositor; the preview layer would
                // show the whole, uncropped camera.
                LivePreviewView(onAttach: capture.attachPreview)
            } else {
                CameraPreviewView(session: capture.session, generation: capture.sessionGeneration,
                                  rotationAngle: capture.cameraRotationAngle)
            }

            if capture.state == .needsAccess {
                accessOverlay
            } else if capture.mode.recordsScreen, capture.state != .preview,
                      capture.screenAccess == .denied || capture.screenAccess == .needsRelaunch {
                screenAccessOverlay
            }
        }
        .overlay(alignment: .top) { notice }
        .overlay(alignment: .bottom) { soundBar }
        .overlay(alignment: .topLeading) { touchCutHints }
    }

    /// The camera going quiet, or a banner - over the top of the preview, where
    /// the sound bar is not.
    @ViewBuilder
    private var notice: some View {
        if capture.cameraIsSilent {
            HStack(spacing: 12) {
                Text("The camera isn't sending a picture. If it's your iPhone, wake it and keep it nearby.")
                if let alternative = capture.alternativeCamera {
                    Button("Use \(alternative.name)") { capture.useAlternativeCamera() }
                        .secondaryActionStyle()
                }
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .floatingSurface(Capsule())
            .padding(12)
        } else if let banner = capture.banner {
            Text(banner)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .floatingSurface(Capsule())
                .padding(12)
        }
    }

    /// The meters and the fader float over the bottom of the preview; after a
    /// take, the player's own controls are there instead.
    @ViewBuilder
    private var soundBar: some View {
        if capture.state != .preview {
            if capture.mode.recordsScreen {
                AudioCrossfaderView(
                    balance: $capture.audioBalance,
                    ducksSystemAudio: $capture.ducksSystemAudio,
                    hasMicrophone: capture.hasAudio,
                    levels: capture.levels
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .floatingSurface(Capsule())
                .padding(14)
            } else if capture.hasAudio {
                // The microphone only: that is what a person can do something about.
                HStack(spacing: 10) {
                    Label("Microphone", systemImage: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VoiceMeterView(levels: capture.levels)
                        .frame(width: 180)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .floatingSurface(Capsule())
                .padding(14)
            }
        }
    }

    /// Touch Cut, before a take: what the trackpad does, shown only while the
    /// pointer is over the preview, so the preview itself stays clear.
    @State private var isHoveringPreview = false

    @ViewBuilder
    private var touchCutHints: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                if capture.mode.cutsOnTouch, capture.state == .ready, isHoveringPreview {
                    HStack(spacing: 8) {
                        hint("Finger on the trackpad → your screen, you in the bubble", systemImage: "hand.point.up.left")
                        hint("Let go → you, full frame", systemImage: "person.crop.rectangle")
                    }
                    .padding(12)
                    .transition(.opacity)
                }
            }
            .onContinuousHover { phase in
                withAnimation(.easeInOut(duration: 0.15)) {
                    if case .active = phase { isHoveringPreview = true } else { isHoveringPreview = false }
                }
            }
    }

    private func hint(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .floatingSurface(Capsule())
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
                        .contentShape(Circle())
                        .frame(width: frame.width * video.width, height: frame.height * video.height)
                        .position(x: video.minX + frame.midX * video.width,
                                  y: video.minY + frame.midY * video.height)
                        .onTapGesture { capture.bubbleCorner = corner }
                        .accessibilityLabel(Text(corner.accessibilityLabel))
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    /// Green-screen mode, before a take: a dashed frame around where you stand,
    /// to drag yourself anywhere on the screen. Fixed during a take, like the corner.
    @ViewBuilder
    private var personHandle: some View {
        if capture.mode.keysPerson, capture.state == .ready, capture.canvasSize.width > 0 {
            GeometryReader { geometry in
                let video = AVMakeRect(aspectRatio: capture.canvasSize,
                                       insideRect: CGRect(origin: .zero, size: geometry.size))
                let canvas = (width: Int(capture.canvasSize.width), height: Int(capture.canvasSize.height))
                let frame = capture.personLayout.normalizedFrame(canvasWidth: canvas.width, canvasHeight: canvas.height,
                                                                 cameraAspect: capture.cameraAspect)
                let rect = CGRect(x: video.minX + frame.minX * video.width, y: video.minY + frame.minY * video.height,
                                  width: frame.width * video.width, height: frame.height * video.height)
                    .intersection(video)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
                    .frame(width: max(0, rect.width), height: max(0, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .overlay {
                        // On the frame's top edge, inside the preview - never over the slide's own title.
                        Label("Drag", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .floatingSurface(Capsule())
                            .position(x: rect.midX, y: max(video.minY + 16, rect.minY))
                            .allowsHitTesting(false)
                    }
                    .gesture(DragGesture()
                        .onChanged { drag in
                            let start = dragStart ?? capture.personLayout
                            if dragStart == nil { dragStart = start }
                            var moved = start
                            moved.center = CGPoint(x: start.center.x + drag.translation.width / video.width,
                                                   y: start.center.y + drag.translation.height / video.height)
                            capture.personLayout = moved.clamped(canvasWidth: canvas.width, canvasHeight: canvas.height,
                                                                 cameraAspect: capture.cameraAspect)
                        }
                        .onEnded { _ in dragStart = nil })
                    .accessibilityLabel("Your position on the screen")
            }
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
            .prominentActionStyle()
        }
        .padding(24)
        .floatingSurface(RoundedRectangle(cornerRadius: 16))
    }

    private var screenAccessOverlay: some View {
        VStack(spacing: 12) {
            Text("Mac-Monologue needs permission to record your screen.")
                .font(.headline)
            Text(capture.screenAccess == .needsRelaunch
                 ? "Permission is on. macOS only applies it after Mac-Monologue restarts."
                 : "Switch on Mac-Monologue under Screen & System Audio Recording, then restart the app — macOS only applies it after a restart.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            HStack(spacing: 12) {
                if capture.screenAccess != .needsRelaunch {
                    Button("Open System Settings…") { capture.openScreenRecordingSettings() }
                        .secondaryActionStyle()
                }
                Button("Restart Mac-Monologue") { capture.relaunch() }
                    .keyboardShortcut(.defaultAction)
                    .prominentActionStyle()
            }
        }
        .padding(24)
        .floatingSurface(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if capture.state == .preview, let url = capture.lastRecordingURL {
                Text([url.lastPathComponent, Self.fileSize(of: url)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                summaryButton
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .bottomBarBackground()
    }

    /// What is about to be recorded, in one line; a click chooses the quality.
    private var summaryButton: some View {
        Button { isShowingQuality.toggle() } label: {
            HStack(spacing: 4) {
                Text(summary)
                    .foregroundStyle(.secondary)
                Text(capture.videoQuality.title)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help("How sharp the video is, and how big the file gets.")
        .disabled(capture.devicePickersLocked)
        .popover(isPresented: $isShowingQuality, arrowEdge: .top) {
            QualityPopover(capture: capture)
        }
    }

    private var summary: String {
        var parts = [capture.mode.shortLabel]
        parts.append(capture.hasAudio ? String(localized: "Microphone on") : String(localized: "No microphone"))
        if capture.mode.recordsScreen { parts.append(String(localized: "Mac sound on")) }
        return parts.joined(separator: " · ") + " ·"
    }

    @ViewBuilder
    private var actions: some View {
        if capture.countdown != nil {
            Text("Esc cancels")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel") { capture.toggleRecording() }
                .keyboardShortcut(.cancelAction)
                .secondaryActionStyle()
                .controlSize(.large)
        } else {
            switch capture.state {
            case .recording:
                timecode(color: .primary)
                Button("Pause", systemImage: "pause.fill") { capture.toggleRecording() }
                    .secondaryActionStyle()
                    .controlSize(.large)
                Button("Finish") { capture.finishTake() }
                    .secondaryActionStyle()
                    .controlSize(.large)
            case .paused:
                timecode(color: .yellow)
                Button("Resume", systemImage: "record.circle") { capture.toggleRecording() }
                    .prominentActionStyle()
                    .tint(.red)
                    .controlSize(.large)
                Button("Finish") { capture.finishTake() }
                    .secondaryActionStyle()
                    .controlSize(.large)
            case .finishing:
                ProgressView().controlSize(.small)
                Text("Finishing…").foregroundStyle(.secondary)
            case .preview:
                Button(capture.isPlaying ? "Pause" : "Play",
                       systemImage: capture.isPlaying ? "pause.fill" : "play.fill") { capture.toggleRecording() }
                    .secondaryActionStyle()
                    .controlSize(.large)
                Button("Reveal in Finder") { capture.revealInFinder() }
                    .secondaryActionStyle()
                    .controlSize(.large)
                Button("New Recording", systemImage: "record.circle") { capture.newRecording() }
                    .prominentActionStyle()
                    .tint(.red)
                    .controlSize(.large)
            case .ready, .needsAccess, .unavailable:
                Button("Record", systemImage: "record.circle") { capture.toggleRecording() }
                    .prominentActionStyle()
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(!capture.canRecord || capture.state != .ready)
            }
        }
    }

    private func timecode(color: Color) -> some View {
        Text(Self.timecode(capture.elapsed))
            .font(.system(.title3, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.trailing, 4)
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

// MARK: - Sidebar

/// The settings of the chosen mode, as a grouped form like System Settings.
/// Fixed during a take - except the sound fader, which floats over the preview.
private struct SidebarForm: View {
    @ObservedObject var capture: CaptureController

    var body: some View {
        Form {
            if capture.devicePickersLocked {
                Section {
                    Label("Fixed while recording. The sound fader stays live.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sources") {
                if capture.mode.recordsScreen {
                    Picker("Screen", selection: $capture.selectedDisplayID) {
                        ForEach(capture.displays) { display in
                            Text(display.displayName).tag(Optional(display.id))
                        }
                    }
                }
                if capture.mode.usesCamera {
                    Picker("Camera", selection: $capture.selectedCameraID) {
                        ForEach(capture.cameras) { option in
                            Text(option.displayName).tag(Optional(option.id))
                        }
                    }
                }
                Picker("Microphone", selection: $capture.selectedMicrophoneID) {
                    ForEach(capture.microphones) { option in
                        Text(option.displayName).tag(Optional(option.id))
                    }
                }
            }
            .disabled(capture.devicePickersLocked)

            if capture.mode.showsBubble {
                Section {
                    Picker("Size", selection: $capture.bubbleSize) {
                        ForEach(BubbleSize.allCases, id: \.self) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Corner") {
                        CornerPickerView(corner: $capture.bubbleCorner)
                    }
                } header: {
                    Text("Camera bubble")
                } footer: {
                    Text("Or click a corner in the preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(capture.devicePickersLocked)
            }

            if capture.mode.cutsOnTouch {
                Section("Touch Cut") {
                    LabeledContent("Finger on the trackpad") { Text("Your screen, you in the bubble") }
                    LabeledContent("Finger lifted") { Text("You, full frame") }
                    Text("During the countdown, the finger decides how the take opens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if capture.mode.keysPerson {
                Section {
                    Picker("Cut out", selection: $capture.keyingChoice) {
                        ForEach(KeyingChoice.allCases, id: \.self) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .help("Automatic uses a green screen when it sees one behind you, and Apple's person detection otherwise.")
                    Slider(value: Binding(get: { capture.personLayout.height },
                                          set: { capture.personLayout.height = $0 }),
                           in: PersonLayout.heightRange) {
                        Text("Your size")
                    }
                    if let inUse = capture.keyingInUse {
                        LabeledContent("In use") {
                            Label(inUse == .greenScreen ? "Green screen found" : "Person detection",
                                  systemImage: "circle.fill")
                                .labelStyle(StatusDotLabelStyle())
                        }
                    }
                } header: {
                    Text("You, cut out")
                } footer: {
                    Text("Drag yourself anywhere in the preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(capture.devicePickersLocked)
            }

            if capture.mode.usesCamera {
                Section("Options") {
                    if capture.framing != .unavailable {
                        // The software zoom would crop the person being cut out.
                        let zoomBlocked = capture.mode.keysPerson && capture.framing == .software
                        Toggle(isOn: $capture.keepsMeInFrame) {
                            Text("Keep me in frame")
                            Text(zoomBlocked ? "Off with Green Screen: the zoom would crop you"
                                 : capture.framing == .centerStage ? "Center Stage" : "Zooms in slightly")
                        }
                        .help(framingHelp)
                        .disabled(zoomBlocked)
                    }
                    Toggle(isOn: $capture.mirrorsRecording) {
                        Text("Mirror the recording")
                        if capture.mirrorsRecording {
                            // On is rarely what anyone wants, and easy to forget:
                            // say what it does for as long as it is on.
                            Label("Text reads backwards in the saved file", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .help(mirrorHelp)
                }
                .disabled(capture.devicePickersLocked)
            }
        }
        .formStyle(.grouped)
    }

    private var framingHelp: String {
        switch capture.framing {
        case .centerStage:
            String(localized: "Uses this camera's Center Stage: it follows you as you move, at full sharpness. You can also switch it in Control Center.")
        case .software, .unavailable:
            String(localized: "Follows your face by zooming in a little and moving with you. The picture gets slightly softer, since part of it is cropped away.")
        }
    }

    private var mirrorHelp: String {
        switch capture.mode {
        case .camera:
            String(localized: "The preview always looks like a mirror. Turn this on only if you want the saved file mirrored too — text you hold up to the camera will then read backwards.")
        case .screenAndCamera:
            String(localized: "Mirrors the camera bubble in the saved file. The screen itself is never mirrored.")
        case .screenAndCameraTouchCut:
            String(localized: "Mirrors the camera — bubble and full picture — in the saved file. The screen itself is never mirrored.")
        case .screenAndGreenScreen:
            String(localized: "Mirrors you in the saved file. The screen behind you is never mirrored.")
        case .screen:
            String(localized: "The screen is never mirrored.")
        }
    }
}

/// A green dot and the text: the way the keying in use is shown.
private struct StatusDotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            Circle().fill(.green).frame(width: 6, height: 6)
            configuration.title
        }
    }
}

// MARK: - Quality

private struct QualityPopover: View {
    @ObservedObject var capture: CaptureController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quality · size for ten minutes")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(VideoQuality.allCases) { quality in
                Button {
                    capture.videoQuality = quality
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                            .opacity(quality == capture.videoQuality ? 1 : 0)
                        Text(quality.title)
                        Spacer(minLength: 24)
                        Text(quality.sizeLabel)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
            if !capture.formatSummary.isEmpty {
                Divider()
                Text(capture.formatSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(minWidth: 260)
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
    ContentView(capture: capture).frame(width: 1100, height: 720)
}

#Preview("Camera · ready") { window(.preview()) }
#Preview("Screen · ready") { window(.preview(mode: .screen)) }
#Preview("Screen + Camera · ready") { window(.preview(mode: .screenAndCamera)) }
#Preview("Touch Cut · ready") { window(.preview(mode: .screenAndCameraTouchCut)) }
#Preview("Screen + Camera · recording") {
    window(.preview(mode: .screenAndCamera, state: .recording, elapsed: 42, audioLevel: -14,
                    systemAudioLevel: -10, audioBalance: -0.4))
}
#Preview("Green Screen · ready") { window(.preview(mode: .screenAndGreenScreen)) }
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
#Preview("No microphone") { window(.preview(hasAudio: false)) }
#Preview("Clipping") { window(.preview(state: .recording, elapsed: 12, audioLevel: -1, isClipping: true)) }
#Preview("Small window") { ContentView(capture: .preview(mode: .screenAndCamera)).frame(width: 900, height: 620) }
#Preview("German") {
    window(.preview(mode: .screenAndCamera)).environment(\.locale, Locale(identifier: "de"))
}
#endif
