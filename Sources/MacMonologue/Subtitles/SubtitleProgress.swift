import Foundation

/// How far subtitles for one take have come, and how long the rest will take.
///
/// The steps take very different times — listening to the whole take is most of
/// it — so each is weighted, and the estimate is the time so far scaled by what
/// is left.
struct SubtitleProgress: Equatable, Sendable {
    enum Step: Equatable, Sendable {
        case listening
        case translating(SubtitleLanguage, index: Int, count: Int)
        case addingToVideo
        case done
    }

    static let listeningWeight = 0.6
    static let translatingWeight = 0.3
    static let addingWeight = 0.1

    let translationCount: Int
    private(set) var step: Step = .listening
    /// 0…1 within the current step.
    private(set) var stepFraction = 0.0

    init(translationCount: Int) {
        self.translationCount = translationCount
    }

    /// Without translations their share goes to listening.
    private var weights: (listening: Double, translating: Double, adding: Double) {
        translationCount == 0
            ? (Self.listeningWeight + Self.translatingWeight, 0, Self.addingWeight)
            : (Self.listeningWeight, Self.translatingWeight, Self.addingWeight)
    }

    mutating func advance(to step: Step, fraction: Double = 0) {
        self.step = step
        stepFraction = min(max(fraction, 0), 1)
    }

    /// 0…1 across all steps; never runs backwards within a take.
    var fraction: Double {
        let w = weights
        switch step {
        case .listening:
            return w.listening * stepFraction
        case .translating(_, let index, let count):
            let perLanguage = w.translating / Double(max(count, 1))
            return w.listening + perLanguage * (Double(index) + stepFraction)
        case .addingToVideo:
            return w.listening + w.translating + w.adding * stepFraction
        case .done:
            return 1
        }
    }

    var percent: Int { Int((fraction * 100).rounded(.down)) }

    /// Seconds left, from the pace so far. Nil until there is enough to go on:
    /// the first few percent say little about the rest.
    func secondsRemaining(elapsed: Double) -> Double? {
        let done = fraction
        guard done >= 0.03, done < 1, elapsed > 0 else { return nil }
        return elapsed / done * (1 - done)
    }

    /// "about 2 min left", "less than a minute left".
    static func remainingLabel(_ seconds: Double?) -> String? {
        guard let seconds else { return nil }
        if seconds < 50 { return "less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        return minutes == 1 ? "about 1 minute left" : "about \(minutes) minutes left"
    }
}
