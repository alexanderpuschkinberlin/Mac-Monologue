import AppKit
import SwiftUI

/// A card under the finished take while its subtitles are made: how far, what
/// is happening, how long it will take — and a way to stop.
struct SubtitleProgressView: View {
    @ObservedObject var subtitles: SubtitleCenter

    var body: some View {
        if let job = subtitles.job {
            HStack(spacing: 14) {
                icon(for: job)
                VStack(alignment: .leading, spacing: 4) {
                    headline(for: job)
                    detail(for: job)
                }
                Spacer(minLength: 8)
                actions(for: job)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.3), value: job.progress.percent)
        }
    }

    @ViewBuilder
    private func icon(for job: SubtitleCenter.Job) -> some View {
        switch job.state {
        case .running:
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: job.progress.fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(job.progress.percent)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 44, height: 44)
        case .finished:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 32)).foregroundStyle(.green)
                .frame(width: 44, height: 44)
        case .cancelled:
            Image(systemName: "stop.circle").font(.system(size: 32)).foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(.orange)
                .frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private func headline(for job: SubtitleCenter.Job) -> some View {
        switch job.state {
        case .running:
            Text("Creating subtitles…").font(.headline)
        case .finished(let languages):
            Text("Subtitles added: " + languages.map { $0.rawValue.uppercased() }.joined(separator: " · "))
                .font(.headline)
        case .cancelled:
            Text("Subtitles cancelled").font(.headline)
        case .failed:
            Text("Subtitles could not be made").font(.headline)
        }
    }

    @ViewBuilder
    private func detail(for job: SubtitleCenter.Job) -> some View {
        switch job.state {
        case .running:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(job.started)
                let remaining = SubtitleProgress.remainingLabel(job.progress.secondsRemaining(elapsed: elapsed))
                Text([Self.describe(job.progress.step), remaining].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .finished:
            Text("Switch them on in your player's subtitles menu. Each language is also saved as an .srt file "
                 + "next to the video.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .cancelled(let kept):
            Text(kept.isEmpty
                 ? "The video is unchanged."
                 : "The video is unchanged. Already finished: "
                    + kept.map { "\($0.rawValue).srt" }.joined(separator: ", ") + ", next to the video.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message + " The video is unchanged.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actions(for job: SubtitleCenter.Job) -> some View {
        switch job.state {
        case .running:
            Button("Cancel") { subtitles.cancel() }
        case .finished:
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([job.video]) }
            closeButton
        case .cancelled, .failed:
            closeButton
        }
    }

    private var closeButton: some View {
        Button {
            subtitles.dismiss()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .help("Close")
    }

    static func describe(_ step: SubtitleProgress.Step) -> String {
        switch step {
        case .listening: "Listening to the take"
        case .translating(let language, let index, let count):
            "Translating to \(language.nativeName) (\(index + 1) of \(count))"
        case .addingToVideo: "Adding them to the video"
        case .done: "Done"
        }
    }
}
