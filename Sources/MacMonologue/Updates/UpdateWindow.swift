import AppKit
import SwiftUI

/// Its own window rather than a sheet: in screen mode the main window may be
/// minimised, and an offer attached to it would never be seen.
@MainActor
final class UpdateWindowController {
    static let shared = UpdateWindowController()
    private var window: NSWindow?

    func show(_ checker: UpdateChecker) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "Software Update"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: UpdateView(checker: checker))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

struct UpdateView: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch checker.state {
        case .checking: "Checking for updates…"
        case .upToDate: "Mac-Monologue is up to date"
        case .failed: "The update did not work"
        case .working: "Updating Mac-Monologue"
        case .available, .idle: "A new version of Mac-Monologue is available"
        }
    }

    private var subtitle: String {
        let installed = checker.installedVersion.description
        switch checker.state {
        case .upToDate:
            return "Version \(installed) is the newest."
        case .available(let releases):
            let newest = releases.first?.version?.description ?? "?"
            return "Version \(newest) — you have \(installed)."
        default:
            return "You have version \(installed)."
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch checker.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .available, .working, .failed:
            changelog
            status
        case .upToDate, .idle:
            EmptyView()
        }
    }

    private var changelog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(ChangelogFormatter.sections(for: checker.availableReleases)) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Version \(section.version)").font(.headline)
                            if let date = section.date {
                                Text(date, format: .dateTime.day().month(.wide).year())
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                        }
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .bullet(let text):
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•")
                                    Text(Self.inline(text))
                                }
                            case .paragraph(let text):
                                Text(Self.inline(text))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
    }

    /// Bold, italics, code and links within a line — the Markdown Text can render.
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    @ViewBuilder
    private var status: some View {
        switch checker.state {
        case .working(let step):
            VStack(alignment: .leading, spacing: 6) {
                switch step {
                case .downloading(let fraction):
                    ProgressView(value: fraction) { Text("Downloading…") }
                case .verifying:
                    ProgressView { Text("Checking it is genuine…") }
                case .installing:
                    ProgressView { Text("Installing — Mac-Monologue will reopen by itself.") }
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        default:
            if let problem = checker.installationProblem, problem != .developmentBuild {
                Label(problem.localizedDescription, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var footer: some View {
        HStack {
            switch checker.state {
            case .available:
                Button("Skip This Version") { checker.skipOffered() }
                Spacer()
                Button("Later") { checker.dismiss() }
                    .keyboardShortcut(.cancelAction)
                if checker.installationProblem == nil {
                    Button("Install and Relaunch") { checker.install() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Download from GitHub") { checker.openReleasesPage() }
                        .keyboardShortcut(.defaultAction)
                }
            case .working(let step):
                Spacer()
                if step != .installing {
                    Button("Cancel") { checker.cancelInstallation() }
                        .keyboardShortcut(.cancelAction)
                }
            case .failed:
                Spacer()
                Button("Close") { checker.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Download from GitHub") { checker.openReleasesPage() }
                    .keyboardShortcut(.defaultAction)
            case .checking, .upToDate, .idle:
                Spacer()
                Button("OK") { checker.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
