import CoreMedia
import XCTest
@testable import Mac_Monologue

private func t(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 600)
}

final class TakeClockTests: XCTestCase {
    func testElapsedIsZeroBeforeStart() {
        let clock = TakeClock()
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: t(10)), .zero)
    }

    func testElapsedRunsWhileRecording() {
        var clock = TakeClock()
        clock.resume(at: t(100))
        XCTAssertEqual(clock.elapsed(at: t(105)).seconds, 5, accuracy: 0.001)
    }

    func testElapsedFreezesWhilePaused() {
        var clock = TakeClock()
        clock.resume(at: t(100))
        clock.pause(at: t(105))
        XCTAssertEqual(clock.elapsed(at: t(200)).seconds, 5, accuracy: 0.001)
    }

    func testPausedIntervalIsRemovedFromTheTimeline() {
        var clock = TakeClock()
        clock.resume(at: t(100))   // 5s of take
        clock.pause(at: t(105))
        clock.resume(at: t(160))   // 55s of dead air, then 3s more
        XCTAssertEqual(clock.elapsed(at: t(163)).seconds, 8, accuracy: 0.001)
    }

    func testTakeTimeIsContinuousAcrossAPause() {
        var clock = TakeClock()
        clock.resume(at: t(100))
        let before = clock.takeTime(for: t(104))
        clock.pause(at: t(105))
        clock.resume(at: t(500))
        let after = clock.takeTime(for: t(501))

        XCTAssertEqual(before?.seconds ?? -1, 4, accuracy: 0.001)
        // 5s recorded before the pause, plus 1s after resuming: no 395s gap.
        XCTAssertEqual(after?.seconds ?? -1, 6, accuracy: 0.001)
    }

    func testSamplesArrivingWhilePausedAreDropped() {
        var clock = TakeClock()
        clock.resume(at: t(100))
        clock.pause(at: t(105))
        XCTAssertNil(clock.takeTime(for: t(106)))
    }

    func testBufferInFlightAcrossResumeIsDropped() {
        var clock = TakeClock()
        clock.resume(at: t(100))
        clock.pause(at: t(105))
        clock.resume(at: t(200))
        // Captured just before the resume point, delivered just after: its content
        // is from during the pause, and reusing the last written timestamp would
        // make AVAssetWriter reject the append.
        XCTAssertNil(clock.takeTime(for: t(199.9)))
    }

    func testTimestampsAreStrictlyIncreasingAcrossAPause() {
        var clock = TakeClock()
        clock.resume(at: t(100))
        let last = clock.takeTime(for: t(104.9))
        clock.pause(at: t(105))
        clock.resume(at: t(200))
        let first = clock.takeTime(for: t(200.033))

        XCTAssertNotNil(last)
        XCTAssertNotNil(first)
        XCTAssertGreaterThan(first!.seconds, last!.seconds)
    }

    func testRedundantResumeIsIgnored() {
        var clock = TakeClock()
        clock.resume(at: t(100))
        clock.resume(at: t(150))   // stray keypress
        XCTAssertEqual(clock.elapsed(at: t(160)).seconds, 60, accuracy: 0.001)
    }

    func testRedundantPauseIsIgnored() {
        var clock = TakeClock()
        clock.resume(at: t(100))
        clock.pause(at: t(110))
        clock.pause(at: t(120))    // stray keypress
        XCTAssertEqual(clock.elapsed(at: t(300)).seconds, 10, accuracy: 0.001)
    }

    func testManyPausesAccumulateCorrectly() {
        var clock = TakeClock()
        var now = 0.0
        for _ in 0..<10 {
            clock.resume(at: t(now))
            now += 2          // 2s recorded
            clock.pause(at: t(now))
            now += 7          // 7s discarded
        }
        XCTAssertEqual(clock.elapsed(at: t(now)).seconds, 20, accuracy: 0.001)
    }
}
