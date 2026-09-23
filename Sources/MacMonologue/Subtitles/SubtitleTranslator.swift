import Foundation
import Translation

/// Translates subtitles on this Mac, with Apple's own translation, keeping each
/// one's time.
@available(macOS 26.0, *)
enum SubtitleTranslator {
    enum TranslationFailure: LocalizedError {
        case notInstalled(from: SubtitleLanguage, to: SubtitleLanguage)

        var errorDescription: String? {
            switch self {
            case .notInstalled(let from, let to):
                "Translation from \(from.englishName) to \(to.englishName) is not downloaded yet. "
                    + "See Settings › Subtitles."
            }
        }
    }

    /// Cues per request: small enough to report progress, large enough to be quick.
    static let batchSize = 20

    static func translate(_ cues: [SubtitleCue], from source: SubtitleLanguage, to target: SubtitleLanguage,
                          progress: @escaping @Sendable (Double) -> Void) async throws -> [SubtitleCue] {
        guard source != target else { return cues }
        let status = await LanguageAvailability().status(from: source.language, to: target.language)
        guard status == .installed else { throw TranslationFailure.notInstalled(from: source, to: target) }

        let session = TranslationSession(installedSource: source.language, target: target.language)
        var translated = cues
        var done = 0
        for batch in stride(from: 0, to: cues.count, by: batchSize).map({ $0..<min($0 + batchSize, cues.count) }) {
            try Task.checkCancellation()
            // Line breaks confuse translation; the translated text is wrapped anew.
            let requests = batch.map { index in
                TranslationSession.Request(sourceText: cues[index].text.replacingOccurrences(of: "\n", with: " "),
                                           clientIdentifier: String(index))
            }
            for response in try await session.translations(from: requests) {
                guard let index = response.clientIdentifier.flatMap(Int.init) else { continue }
                translated[index].text = SubtitleSegmenter.wrap(response.targetText)
            }
            done += batch.count
            progress(Double(done) / Double(max(cues.count, 1)))
        }
        return translated
    }
}
