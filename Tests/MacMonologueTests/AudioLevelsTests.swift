import XCTest
@testable import Mac_Monologue

/// The meters publish only what the eye can see: every publish costs a redraw.
@MainActor
final class AudioLevelsTests: XCTestCase {
    func testASmallWobbleIsNotPublished() {
        let levels = AudioLevels()
        levels.setVoice(AudioLevels.Reading(level: -20, peak: -12))
        levels.setVoice(AudioLevels.Reading(level: -20.3, peak: -12.2))
        XCTAssertEqual(levels.voice.level, -20)
    }

    func testAVisibleChangeIsPublished() {
        let levels = AudioLevels()
        levels.setVoice(AudioLevels.Reading(level: -20, peak: -12))
        levels.setVoice(AudioLevels.Reading(level: -19.4, peak: -12))
        XCTAssertEqual(levels.voice.level, -19.4)
    }

    func testClippingAlwaysShows() {
        let levels = AudioLevels()
        levels.setVoice(AudioLevels.Reading(level: -1, peak: -0.1))
        levels.setVoice(AudioLevels.Reading(level: -1, peak: -0.1, isClipping: true))
        XCTAssertTrue(levels.voice.isClipping)
    }

    func testSilenceStaysSilentWithoutPublishing() {
        let levels = AudioLevels()
        var publishes = 0
        let watch = levels.objectWillChange.sink { publishes += 1 }
        for _ in 0..<100 { levels.setSystem(.silent) }
        XCTAssertEqual(publishes, 0)
        watch.cancel()
    }
}
