import AVFoundation
import Foundation
import Speech

/// Listens to a finished take and writes down what was said, word by word with
/// its time — on this Mac, with Apple's own speech recognition.
@available(macOS 26.0, *)
enum SubtitleTranscriber {
    enum TranscriptionError: LocalizedError {
        case languageNotSupported(SubtitleLanguage)
        case languageNotInstalled(SubtitleLanguage)
        case noSound

        var errorDescription: String? {
            switch self {
            case .languageNotSupported(let language):
                "This Mac cannot recognise \(language.englishName)."
            case .languageNotInstalled(let language):
                "\(language.englishName) speech recognition is not downloaded yet. See Settings › Subtitles."
            case .noSound:
                "This take has no sound to make subtitles from."
            }
        }
    }

    /// `progress` runs from 0 to 1 by how far into the take recognition has got.
    static func words(in video: URL, language: SubtitleLanguage,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> [TimedWord] {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language.speechLocale) else {
            throw TranscriptionError.languageNotSupported(language)
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        // A locale has to be reserved by this app before its model can be used,
        // even when another app downloaded it.
        if !(await AssetInventory.reservedLocales).contains(locale) {
            _ = try? await AssetInventory.reserve(locale: locale)
        }
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw TranscriptionError.languageNotInstalled(language)
        }

        let audio = try await soundtrack(of: video)
        defer { try? FileManager.default.removeItem(at: audio) }
        let file = try AVAudioFile(forReading: audio)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration > 0 else { throw TranscriptionError.noSound }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        return try await withTaskCancellationHandler {
            async let collected: [TimedWord] = collect(transcriber.results, duration: duration, progress: progress)
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            return try await collected
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// Recognition hands back runs of text, each a word — or a piece of one, or
    /// its punctuation — with a time range. A leading space starts a new word.
    private static func collect(_ results: some AsyncSequence<SpeechTranscriber.Result, any Error>,
                                duration: Double,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> [TimedWord] {
        var words: [TimedWord] = []
        for try await result in results {
            try Task.checkCancellation()
            for run in result.text.runs {
                guard let range = run.audioTimeRange else { continue }
                let piece = String(result.text[run.range].characters)
                let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let startsWord = piece.first?.isWhitespace ?? true
                if !startsWord, var last = words.popLast() {
                    last.text += trimmed
                    last.end = range.end.seconds
                    words.append(last)
                } else {
                    words.append(TimedWord(text: trimmed, start: range.start.seconds, end: range.end.seconds))
                }
            }
            progress(min(1, result.range.end.seconds / duration))
        }
        return words
    }

    /// The take's sound on its own, as a temporary file speech recognition can
    /// read — it does not open a video file.
    private static func soundtrack(of video: URL) async throws -> URL {
        let asset = AVURLAsset(url: video)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw TranscriptionError.noSound
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.noSound
        }
        try await export.export(to: output, as: .m4a)
        return output
    }
}
