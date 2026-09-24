import SwiftUI

/// Which language you speak and which subtitles you want, with what each still
/// needs from Apple. The same in the welcome steps and in Settings.
struct SubtitleLanguagePicker: View {
    @ObservedObject var subtitles: SubtitleCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("In my videos I speak")
                Picker("Spoken language", selection: $subtitles.spokenLanguage) {
                    ForEach(SubtitleLanguage.allCases) { language in
                        Text(language.englishName).tag(language)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Add subtitles in").font(.headline)
                HStack(spacing: 10) {
                    ForEach(SubtitleLanguage.allCases) { language in
                        card(language)
                    }
                }
                Text("Choose one, several, or none.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            downloadNote
        }
        .onAppear { subtitles.refreshReadiness() }
    }

    private func card(_ language: SubtitleLanguage) -> some View {
        let isOn = subtitles.languages.contains(language)
        return Button {
            if isOn { subtitles.languages.remove(language) } else { subtitles.languages.insert(language) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(language.nativeName).font(.headline)
                    Spacer(minLength: 0)
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                }
                if language == subtitles.spokenLanguage {
                    Text("as spoken").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("translated").font(.caption).foregroundStyle(.secondary)
                }
                if isOn { status(subtitles.readiness[language] ?? .checking) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(isOn ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isOn ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.nativeName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func status(_ readiness: LanguageReadiness) -> some View {
        let (symbol, color): (String, Color) = switch readiness {
        case .ready: ("checkmark.circle.fill", .green)
        case .needsDownload: ("arrow.down.circle", .orange)
        case .unsupported: ("xmark.circle", .red)
        case .checking: ("ellipsis.circle", .secondary)
        }
        return Label(readiness.label, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var downloadNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Subtitles are made on this Mac, with its own built-in tools. Nothing you record is "
                     + "uploaded. The first time, your Mac may need to download language tools from Apple: "
                     + "once per language, and it can take a few minutes.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if let progress = subtitles.speechDownloadProgress {
                ProgressView(value: progress) {
                    Text("Downloading \(subtitles.spokenLanguage.englishName) speech recognition… "
                         + "\(Int(progress * 100)) %")
                        .font(.caption)
                }
            } else if let configuration = subtitles.translationToPrepare,
                      let target = configuration.target,
                      let language = SubtitleLanguage.allCases.first(where: { $0.language.minimalIdentifier == target.minimalIdentifier }) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Getting the \(language.englishName) translation. macOS may ask you to confirm.")
                        .font(.caption)
                }
            } else if subtitles.needsDownload {
                Button("Download Language Tools") { subtitles.downloadMissing() }
            }

            if let error = subtitles.downloadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }
}

#if DEBUG
#Preview("Ready") { SubtitleLanguagePicker(subtitles: .preview()).padding(20).frame(width: 560) }
#Preview("Needs download") {
    SubtitleLanguagePicker(subtitles: .preview(languages: [.german, .french])).padding(20).frame(width: 560)
}
#Preview("Downloading speech") {
    SubtitleLanguagePicker(subtitles: .preview(languages: [.german, .french], speechDownloadProgress: 0.35))
        .padding(20).frame(width: 560)
}
#Preview("Checking") {
    SubtitleLanguagePicker(subtitles: .preview(readiness: [:])).padding(20).frame(width: 560)
}
#Preview("Unsupported and error") {
    SubtitleLanguagePicker(subtitles: .preview(
        languages: [.german, .spanish],
        readiness: [.german: .ready, .english: .ready, .french: .ready, .spanish: .unsupported],
        downloadError: "German speech recognition could not be downloaded: The Internet connection appears to be offline."))
        .padding(20).frame(width: 560)
}
#Preview("All four") {
    SubtitleLanguagePicker(subtitles: .preview(languages: [.german, .english, .french, .spanish],
                                               readiness: [.german: .ready, .english: .ready, .french: .ready, .spanish: .ready]))
        .padding(20).frame(width: 560)
}
#endif
