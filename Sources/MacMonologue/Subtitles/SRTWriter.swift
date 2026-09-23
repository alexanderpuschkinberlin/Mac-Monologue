import Foundation

/// SubRip, the subtitle format every video site and player reads.
enum SRTWriter {
    static func srt(for cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// HH:MM:SS,mmm — with a comma, as the format wants.
    static func timestamp(_ seconds: Double) -> String {
        let milliseconds = max(0, Int((seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d",
                      milliseconds / 3_600_000, milliseconds / 60_000 % 60,
                      milliseconds / 1000 % 60, milliseconds % 1000)
    }

    /// "Take 2026-09-24 10.15.mp4" → "Take 2026-09-24 10.15.de.srt", next to it.
    /// The language before the extension is what VLC and most sites look for.
    static func url(nextTo video: URL, language: SubtitleLanguage) -> URL {
        video.deletingPathExtension().appendingPathExtension(language.rawValue).appendingPathExtension("srt")
    }
}
