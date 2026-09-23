import SwiftUI

/// When the app opens, which mode it starts in.
enum LaunchMode: String, CaseIterable, Identifiable, Sendable {
    case lastUsed
    case camera
    case screenAndCamera

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastUsed: "The mode I used last"
        case .camera: "Camera"
        case .screenAndCamera: "Screen + Camera"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var capture: CaptureController
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        TabView {
            shortcuts
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            recording
                .tabItem { Label("Recording", systemImage: "record.circle") }
            permissions
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 520)
        .padding(.vertical, 8)
    }

    // MARK: - Shortcuts

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("These work from any app — so you can pause and finish while presenting, "
                 + "without switching back to Mac-Monologue.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            shortcutRow(title: "Record, pause and resume",
                        shortcut: $capture.toggleShortcut,
                        defaultShortcut: .defaultToggle,
                        action: .toggleRecording)
            shortcutRow(title: "Finish the take",
                        shortcut: $capture.finishShortcut,
                        defaultShortcut: .defaultFinish,
                        action: .finish)
        }
        .padding(20)
    }

    private func shortcutRow(title: String, shortcut: Binding<Shortcut>,
                             defaultShortcut: Shortcut, action: GlobalHotkeys.Action) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(shortcut.wrappedValue.displayString)
                    .font(.system(.title3, design: .monospaced))
            }
            KeyCapView(shortcut: shortcut.wrappedValue)
            ShortcutRecorderButton(shortcut: shortcut, defaultShortcut: defaultShortcut) { recording in
                capture.setHotkeysSuspended(recording)
            }
            if capture.unavailableShortcuts.contains(action) {
                Label("Another app already uses this combination. Choose a different one.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Recording

    private var recording: some View {
        Form {
            Picker("When Mac-Monologue opens", selection: $capture.launchMode) {
                ForEach(LaunchMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Section("Screen + Camera") {
                Toggle("Minimise the window while recording", isOn: $capture.autoMinimizes)
                Text("Keeps it off the slides you are presenting. It is never in the recording either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show mouse clicks", isOn: $capture.showsMouseClicks)
                Text("Marks every click in the recording, so viewers can follow along.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recordings") {
                HStack {
                    Text("Saved to ~/Movies/Monologue")
                    Spacer()
                    Button("Show in Finder") { capture.revealInFinder() }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Updates

    private var updatesTab: some View {
        Form {
            Section {
                Toggle("Automatically check for updates", isOn: $updates.checksAutomatically)
                Text("Asks GitHub for the newest version when Mac-Monologue opens and once a day. "
                     + "Nothing else leaves your Mac, and nothing is installed without asking you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                LabeledContent("Installed version", value: updates.installedVersion.description)
                LabeledContent("Last checked") {
                    if let lastCheck = updates.lastCheck {
                        Text(lastCheck, format: .relative(presentation: .named))
                    } else {
                        Text("Never")
                    }
                }
                HStack {
                    Button("Check Now") { updates.checkNow(userInitiated: true) }
                    Spacer()
                    Button("Release Notes on GitHub") { NSWorkspace.shared.open(ReleaseFeed.pageURL) }
                        .buttonStyle(.link)
                }
            }
            if let problem = updates.installationProblem {
                Section {
                    Label(problem.localizedDescription, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Permissions

    private var permissions: some View {
        // Re-read every couple of seconds: permissions change in System Settings,
        // not here, and nothing tells the app when they do.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            Form {
                Section {
                    ForEach(Permission.allCases) { permission in
                        HStack {
                            PermissionBadge(status: permission.status)
                            Text(permission.title)
                            Spacer()
                            if permission.status != .granted {
                                Button("Open System Settings…") { permission.openSettings() }
                            }
                        }
                    }
                } footer: {
                    Text("Screen recording only takes effect after Mac-Monologue restarts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Show the Welcome Steps Again…") { capture.showOnboarding() }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct PermissionBadge: View {
    let status: Permission.Status

    var body: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel("Allowed")
        case .notAsked:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                .accessibilityLabel("Not allowed yet")
        case .denied:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                .accessibilityLabel("Not allowed")
        }
    }
}
