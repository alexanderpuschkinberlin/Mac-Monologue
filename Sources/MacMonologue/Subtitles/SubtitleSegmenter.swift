import Foundation

/// Turns a stream of timed words into subtitles people can read: at most two
/// lines of about 42 characters, on screen for one to seven seconds, broken at
/// the end of a sentence or a pause where possible.
///
/// These are the usual broadcast limits; longer lines or shorter cues cannot be
/// read before they are gone.
enum SubtitleSegmenter {
    static let maxLineLength = 42
    static let maxLines = 2
    static let minDuration = 1.0
    static let maxDuration = 7.0
    /// A silence this long ends a subtitle: the next words belong to a new thought.
    static let pauseBreak = 0.8
    /// Past this length, the end of a sentence is a good place to break.
    static let sentenceBreakLength = 20

    static func cues(from words: [TimedWord]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var current: [TimedWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ")
            cues.append(SubtitleCue(start: first.start, end: last.end, text: wrap(text)))
            current = []
        }

        for word in words where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if let first = current.first, let last = current.last {
                let length = (current.map(\.text) + [word.text]).joined(separator: " ").count
                let tooLong = length > maxLineLength * maxLines
                let tooSlow = word.end - first.start > maxDuration
                let paused = word.start - last.end >= pauseBreak
                let sentenceEnded = last.text.last.map { ".?!".contains($0) } ?? false
                let sentenceLength = current.map(\.text).joined(separator: " ").count
                if tooLong || tooSlow || paused || (sentenceEnded && sentenceLength >= sentenceBreakLength) {
                    flush()
                }
            }
            current.append(word)
        }
        flush()
        return withReadableDurations(cues)
    }

    /// Stretches cues that flash by too fast to `minDuration`, without running
    /// into the next one.
    static func withReadableDurations(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        var result = cues
        for index in result.indices where result[index].end - result[index].start < minDuration {
            let wanted = result[index].start + minDuration
            let limit = index + 1 < result.count ? result[index + 1].start : wanted
            result[index].end = max(result[index].end, min(wanted, limit))
        }
        return result
    }

    /// One line if it fits, else two, split at the space nearest the middle —
    /// balanced lines read faster than a long line over a short one.
    static func wrap(_ text: String) -> String {
        let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.count > maxLineLength else { return text }
        let middle = text.count / 2
        let spaces = text.indices.filter { text[$0] == " " }
        guard let split = spaces.min(by: {
            abs(text.distance(from: text.startIndex, to: $0) - middle)
                < abs(text.distance(from: text.startIndex, to: $1) - middle)
        }) else { return text }
        return text[..<split] + "\n" + text[text.index(after: split)...]
    }
}
