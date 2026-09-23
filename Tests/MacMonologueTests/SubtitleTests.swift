import XCTest
@testable import Mac_Monologue

final class SubtitleSegmenterTests: XCTestCase {
    /// Words spoken one after another, `pace` seconds each.
    private func words(_ text: String, from start: Double = 0, pace: Double = 0.3) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { index, word in
            TimedWord(text: String(word), start: start + Double(index) * pace,
                      end: start + Double(index + 1) * pace - 0.05)
        }
    }

    func testShortSentenceIsOneCueOnOneLine() {
        let cues = SubtitleSegmenter.cues(from: words("Hello and welcome."))
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Hello and welcome.")
    }

    func testNoCueIsLongerThanTwoLinesOfFortyTwo() {
        let long = Array(repeating: "presentation", count: 40).joined(separator: " ")
        for cue in SubtitleSegmenter.cues(from: words(long)) {
            let lines = cue.text.split(separator: "\n")
            XCTAssertLessThanOrEqual(lines.count, 2)
            for line in lines { XCTAssertLessThanOrEqual(line.count, SubtitleSegmenter.maxLineLength, cue.text) }
        }
    }

    func testNoCueStaysLongerThanSevenSeconds() {
        let slow = words("one two three four five six seven eight nine ten eleven", pace: 1.2)
        for cue in SubtitleSegmenter.cues(from: slow) {
            XCTAssertLessThanOrEqual(cue.end - cue.start, SubtitleSegmenter.maxDuration)
        }
    }

    func testBreaksAtTheEndOfASentence() {
        let cues = SubtitleSegmenter.cues(from: words("This is the first sentence here. And this is the second one."))
        XCTAssertEqual(cues.map(\.text), ["This is the first sentence here.", "And this is the second one."])
    }

    func testBreaksAtAPause() {
        let cues = SubtitleSegmenter.cues(from: words("So far so good", from: 0) + words("then later", from: 5))
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[1].text, "then later")
    }

    func testAFlashIsStretchedButNotIntoTheNextCue() {
        let cues = SubtitleSegmenter.withReadableDurations([
            SubtitleCue(start: 0, end: 0.3, text: "Hi."),
            SubtitleCue(start: 0.6, end: 2, text: "Next"),
            SubtitleCue(start: 5, end: 5.2, text: "Bye."),
        ])
        XCTAssertEqual(cues[0].end, 0.6, accuracy: 0.0001)
        XCTAssertEqual(cues[2].end, 6, accuracy: 0.0001)
    }

    func testTwoLinesAreBalanced() {
        let wrapped = SubtitleSegmenter.wrap("Today I want to show you how the new quarterly planning works")
        let lines = wrapped.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertLessThan(abs(lines[0].count - lines[1].count), 12)
    }

    func testNoWordsNoCues() {
        XCTAssertEqual(SubtitleSegmenter.cues(from: []), [])
    }
}

final class SRTWriterTests: XCTestCase {
    func testWritesNumberedCuesWithCommaMilliseconds() {
        let srt = SRTWriter.srt(for: [
            SubtitleCue(start: 1.5, end: 3.25, text: "Hello"),
            SubtitleCue(start: 3661.001, end: 3662, text: "Line one\nLine two"),
        ])
        XCTAssertEqual(srt, """
        1
        00:00:01,500 --> 00:00:03,250
        Hello

        2
        01:01:01,001 --> 01:01:02,000
        Line one
        Line two

        """)
    }

    func testFileSitsNextToTheVideoWithTheLanguageInItsName() {
        let video = URL(fileURLWithPath: "/Movies/Monologue/Take 10.15.mp4")
        XCTAssertEqual(SRTWriter.url(nextTo: video, language: .french).lastPathComponent, "Take 10.15.fr.srt")
    }
}

final class SubtitleProgressTests: XCTestCase {
    func testWeightsAddUpAcrossSteps() {
        var progress = SubtitleProgress(translationCount: 2)
        XCTAssertEqual(progress.fraction, 0)
        progress.advance(to: .listening, fraction: 1)
        XCTAssertEqual(progress.fraction, 0.6, accuracy: 0.0001)
        progress.advance(to: .translating(.english, index: 1, count: 2), fraction: 0)
        XCTAssertEqual(progress.fraction, 0.75, accuracy: 0.0001)
        progress.advance(to: .addingToVideo, fraction: 0.5)
        XCTAssertEqual(progress.fraction, 0.95, accuracy: 0.0001)
        progress.advance(to: .done)
        XCTAssertEqual(progress.percent, 100)
    }

    func testWithoutTranslationsListeningCountsForMore() {
        var progress = SubtitleProgress(translationCount: 0)
        progress.advance(to: .listening, fraction: 1)
        XCTAssertEqual(progress.fraction, 0.9, accuracy: 0.0001)
    }

    func testRemainingTimeFollowsThePaceSoFar() {
        var progress = SubtitleProgress(translationCount: 1)
        progress.advance(to: .listening, fraction: 0.5)          // 30 % done
        XCTAssertEqual(progress.secondsRemaining(elapsed: 30) ?? 0, 70, accuracy: 0.001)
    }

    func testNoEstimateFromTooLittle() {
        var progress = SubtitleProgress(translationCount: 1)
        progress.advance(to: .listening, fraction: 0.01)
        XCTAssertNil(progress.secondsRemaining(elapsed: 2))
    }

    func testRemainingLabels() {
        XCTAssertEqual(SubtitleProgress.remainingLabel(20), "less than a minute left")
        XCTAssertEqual(SubtitleProgress.remainingLabel(70), "about 1 minute left")
        XCTAssertEqual(SubtitleProgress.remainingLabel(160), "about 3 minutes left")
        XCTAssertNil(SubtitleProgress.remainingLabel(nil))
    }
}
