import Foundation
import Speech
import Translation

/// Whether this Mac has what it needs to make subtitles in a language.
enum LanguageReadiness: Equatable, Sendable {
    case ready
    case needsDownload
    case unsupported
    case checking

    var label: String {
        switch self {
        case .ready: "Ready"
        case .needsDownload: "Needs a download from Apple"
        case .unsupported: "Not available on this Mac"
        case .checking: "Checking…"
        }
    }
}

/// The language tools subtitles need: speech recognition for the spoken
/// language, and a translation pack for each other one.
@available(macOS 26.0, *)
enum SubtitleAssets {
    /// Ready only if both recognising `spoken` and translating it into `target` are.
    static func readiness(spoken: SubtitleLanguage, target: SubtitleLanguage) async -> LanguageReadiness {
        let speech = await speechReadiness(spoken)
        guard speech != .unsupported else { return .unsupported }
        guard target != spoken else { return speech }
        let translation: LanguageReadiness
        switch await LanguageAvailability().status(from: spoken.language, to: target.language) {
        case .installed: translation = .ready
        case .supported: translation = .needsDownload
        case .unsupported: translation = .unsupported
        @unknown default: translation = .unsupported
        }
        if translation == .unsupported { return .unsupported }
        return speech == .ready && translation == .ready ? .ready : .needsDownload
    }

    static func speechReadiness(_ language: SubtitleLanguage) async -> LanguageReadiness {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language.speechLocale)
        else { return .unsupported }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains(locale) ? .ready : .needsDownload
    }

    /// Downloads speech recognition for `language`, reporting 0…1.
    static func downloadSpeech(_ language: SubtitleLanguage,
                               progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language.speechLocale) else { return }
        if !(await AssetInventory.reservedLocales).contains(locale) {
            _ = try await AssetInventory.reserve(locale: locale)
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            progress(1)
            return
        }
        let watcher = Task {
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { watcher.cancel() }
        try await request.downloadAndInstall()
        progress(1)
    }
}
