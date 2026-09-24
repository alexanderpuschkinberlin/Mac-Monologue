import CoreGraphics
import SwiftUI

/// The first thing a new user sees: what the app does, the permissions it needs
/// — each asked for only after saying why — and the shortcuts, drawn.
struct OnboardingView: View {
    @ObservedObject var capture: CaptureController

    private enum Step: Int, CaseIterable {
        case welcome, camera, microphone, screen, quality, subtitles, shortcuts, done
    }

    @State private var step: Step = .welcome
    /// Screen recording granted during these steps needs a restart to take effect.
    @State private var screenGrantedAtStart = CGPreflightScreenCaptureAccess()
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            // Re-read every second while a step waits on System Settings.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(28)
            }

            Divider()

            HStack {
                progress
                Spacer()
                if step != .welcome, step != .done {
                    Button("Back") { move(-1) }
                }
                primaryButton
            }
            .padding(16)
        }
        .frame(width: 600, height: 560)
        .modifier(TranslationPreparation(subtitles: capture.subtitles))
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            page(symbol: "record.circle",
                 title: "Welcome to Mac-Monologue",
                 text: "Record yourself talking — or your screen with you in a small circle in the corner, "
                     + "like the tutorials you see on YouTube. Press one key to start, the same key to "
                     + "pause, and your video is ready. No editing afterwards.")
        case .camera:
            permissionPage(.camera, symbol: "camera",
                           text: "So you can be seen: on your own, or in the circle next to your slides.")
        case .microphone:
            permissionPage(.microphone, symbol: "mic",
                           text: "So you can be heard. The level meter shows how loud you are before you start.")
        case .screen:
            permissionPage(.screen, symbol: "rectangle.on.rectangle",
                           text: "So you can record presentations and demos. Mac-Monologue only records "
                               + "while you are recording, and never records its own window.")
        case .quality:
            qualityPage
        case .subtitles:
            subtitlesPage
        case .shortcuts:
            shortcutsPage
        case .done:
            donePage
        }
    }

    private func page(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.weight(.semibold))
            Text(text)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionPage(_ permission: Permission, symbol: String, text: String) -> some View {
        VStack(spacing: 20) {
            page(symbol: symbol, title: permission.title, text: text)

            switch permission.status {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            case .notAsked:
                if permission == .screen {
                    Text("macOS will send you to System Settings: switch on Mac-Monologue under "
                         + "“Screen & System Audio Recording”, then come back here.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 440)
                }
            case .denied:
                VStack(spacing: 8) {
                    Text("This was turned off earlier, so macOS will not ask again.")
                        .foregroundStyle(.secondary)
                    Button("Open System Settings…") { permission.openSettings() }
                }
            }
        }
    }

    private var qualityPage: some View {
        VStack(spacing: 12) {
            Text("How sharp should your videos be?")
                .font(.title.weight(.semibold))
            Text("Sharper means bigger files. Pick what suits how you share your videos: "
                 + "by email, as a link, or for editing. Medium fits most people.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .fixedSize(horizontal: false, vertical: true)
            QualityCards(selection: $capture.videoQuality)
                .frame(maxWidth: 520)
            Text("You can change this any time, in the main window or in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitlesPage: some View {
        VStack(spacing: 12) {
            Text("Subtitles, made by your Mac")
                .font(.title.weight(.semibold))
            Text("After each take, your Mac can write down what you said and add it as subtitles, "
                 + "in the language you speak and translated. Viewers switch them on in their player, "
                 + "and each language is also saved as a file for YouTube or Vimeo.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
                .fixedSize(horizontal: false, vertical: true)
            SubtitleLanguagePicker(subtitles: capture.subtitles)
                .frame(maxWidth: 540)
            Text("You can change this any time in Settings › Subtitles.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var shortcutsPage: some View {
        VStack(spacing: 14) {
            Text("Control it from anywhere")
                .font(.title.weight(.semibold))
            Text("While you present, your slides are in front. These keys still reach Mac-Monologue.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: 16) {
                shortcutCard(title: "Record · Pause · Resume", shortcut: capture.toggleShortcut)
                shortcutCard(title: "Finish", shortcut: capture.finishShortcut)
            }
            Text("You can change them later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutCard(title: String, shortcut: Shortcut) -> some View {
        VStack(spacing: 6) {
            KeyCapView(shortcut: shortcut)
                .scaleEffect(0.72)
                .frame(width: KeyCapView.size.width * 0.72, height: KeyCapView.size.height * 0.72)
            Text(title).font(.headline)
            Text(shortcut.displayString).font(.system(.body, design: .monospaced))
        }
    }

    @ViewBuilder
    private var donePage: some View {
        if needsRestart {
            page(symbol: "arrow.clockwise.circle",
                 title: "One restart, and you are set",
                 text: "macOS only lets Mac-Monologue see your screen after it restarts. "
                     + "It takes a second and opens again right away.")
        } else {
            page(symbol: "checkmark.circle",
                 title: "Ready",
                 text: "Choose Camera, Screen or Screen + Camera at the top, press Record, and talk.")
        }
    }

    // MARK: - Navigation

    private var needsRestart: Bool {
        !screenGrantedAtStart && Permission.screen.status == .granted
    }

    private var currentPermission: Permission? {
        switch step {
        case .camera: .camera
        case .microphone: .microphone
        case .screen: .screen
        default: nil
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if step == .done {
            Button(needsRestart ? "Restart Mac-Monologue" : "Start Recording") {
                capture.completeOnboarding(relaunch: needsRestart)
            }
            .keyboardShortcut(.defaultAction)
        } else if step == .subtitles {
            SubtitleStepButtons(subtitles: capture.subtitles) { move(1) }
        } else if let permission = currentPermission, permission.status == .notAsked {
            HStack {
                Button("Not Now") { move(1) }
                Button("Allow \(permission.title)…") {
                    isRequesting = true
                    Task {
                        _ = await permission.request()
                        isRequesting = false
                        // The screen prompt returns before the user has decided in
                        // System Settings; stay on the step until they have.
                        if permission.status == .granted { move(1) }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRequesting)
            }
        } else {
            Button("Continue") { move(1) }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases.filter { $0 != .subtitles || SubtitleCenter.isSupported }, id: \.self) { candidate in
                Circle()
                    .fill(candidate == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private func move(_ delta: Int) {
        guard var next = Step(rawValue: step.rawValue + delta) else { return }
        // Subtitles need macOS 26; before that the step is not shown at all.
        if next == .subtitles, !SubtitleCenter.isSupported,
           let skipped = Step(rawValue: next.rawValue + delta) {
            next = skipped
        }
        step = next
    }
}

/// The subtitles step's buttons, in a view of their own so they follow
/// `SubtitleCenter`: the welcome steps observe only the capture controller, and
/// a Continue button reading the subtitle choice through it stayed greyed out
/// after languages were picked.
///
/// When the chosen languages still need tools from Apple, Continue fetches them
/// and waits, showing the progress in the picker above — or moves on and lets
/// them finish in the background.
private struct SubtitleStepButtons: View {
    @ObservedObject var subtitles: SubtitleCenter
    let onContinue: () -> Void

    @State private var isWaitingForDownload = false

    var body: some View {
        HStack {
            if isWaitingForDownload, subtitles.downloadError != nil {
                Button("Continue Without") {
                    subtitles.isEnabled = false
                    isWaitingForDownload = false
                    onContinue()
                }
                Button("Try Again") { subtitles.downloadMissing() }
                    .keyboardShortcut(.defaultAction)
            } else if isWaitingForDownload {
                Button("Continue in Background") {
                    isWaitingForDownload = false
                    onContinue()
                }
                Button {
                } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Downloading…")
                    }
                }
                .disabled(true)
            } else {
                Button("Not Now") {
                    subtitles.isEnabled = false
                    onContinue()
                }
                Button("Continue") {
                    subtitles.isEnabled = true
                    if subtitles.needsDownload {
                        isWaitingForDownload = true
                        subtitles.downloadMissing()
                    } else {
                        onContinue()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(subtitles.languages.isEmpty)
            }
        }
        .onChange(of: subtitles.readiness) { continueIfReady() }
        .onChange(of: subtitles.isDownloading) { continueIfReady() }
    }

    /// Everything chosen is there — or cannot be had on this Mac, which waiting
    /// would not change.
    private func continueIfReady() {
        guard isWaitingForDownload, !subtitles.isDownloading, subtitles.downloadError == nil,
              !subtitles.needsDownload,
              !subtitles.orderedLanguages.contains(where: { subtitles.readiness[$0] == .checking })
        else { return }
        isWaitingForDownload = false
        onContinue()
    }
}
