import XCTest
@testable import Mac_Monologue

/// The rules that decide whether mixed audio clicks, shifts or drifts — tested
/// with synthetic samples, because those failures are hard to hear reliably and
/// impossible to reproduce on demand with real devices.
final class AudioMixerCoreTests: XCTestCase {
    private let block = AudioMixerCore.blockFrames
    private let holdBack = Int(AudioMixerCore.holdBackFrames)

    private func constant(_ value: Float, _ count: Int) -> [Float] {
        Array(repeating: value, count: count)
    }

    private func samples(_ blocks: [AudioMixerCore.Block]) -> [Float] {
        blocks.flatMap(\.samples)
    }

    func testMicrophoneOnly() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.pushMicrophone(constant(0.5, block * 2 + holdBack), reportedIndex: 0)
        let out = mixer.drainReadyBlocks()
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(samples(out), constant(0.5, block * 2))
    }

    func testSystemOnlyWhenThereIsNoMicrophone() {
        var mixer = AudioMixerCore(microphoneIsMaster: false)
        mixer.pushSystem(constant(0.3, block + holdBack), reportedIndex: 0)
        XCTAssertEqual(samples(mixer.drainReadyBlocks()), constant(0.3, block))
    }

    func testBothAreSummed() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.pushSystem(constant(0.5, block + holdBack), reportedIndex: 0)
        mixer.pushMicrophone(constant(0.25, block + holdBack), reportedIndex: 0)
        XCTAssertEqual(samples(mixer.drainReadyBlocks()), constant(0.75, block))
    }

    func testTheSumIsClampedRatherThanWrappingAround() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.pushSystem(constant(0.8, block + holdBack), reportedIndex: 0)
        mixer.pushMicrophone(constant(0.8, block + holdBack), reportedIndex: 0)
        XCTAssertEqual(samples(mixer.drainReadyBlocks()), constant(1, block))
    }

    func testNothingIsEmittedInsideTheHoldBack() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.pushMicrophone(constant(0.1, block + holdBack - 1), reportedIndex: 0)
        XCTAssertTrue(mixer.drainReadyBlocks().isEmpty)
        mixer.pushMicrophone([0.1], reportedIndex: Int64(block + holdBack - 1))
        XCTAssertEqual(mixer.drainReadyBlocks().count, 1)
    }

    func testBlocksAreContiguous() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.pushMicrophone(constant(0.1, block * 5 + holdBack), reportedIndex: 1_000)
        let out = mixer.drainReadyBlocks()
        XCTAssertEqual(out.map(\.startIndex), (0..<5).map { 1_000 + Int64($0 * block) })
    }

    /// A hole in system audio must read as silence at exactly that span — and must
    /// not pull what follows it earlier, which is what would put speech and music
    /// out of step for the rest of the take.
    func testAHoleInSystemAudioIsSilenceNotAShift() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        let hole = 2_400                                          // 50 ms
        mixer.pushSystem(constant(0.1, 9_600), reportedIndex: 0)
        mixer.pushSystem(constant(0.2, 12_000), reportedIndex: Int64(9_600 + hole))
        mixer.pushMicrophone(constant(0, 24_000 + holdBack), reportedIndex: 0)

        let out = samples(mixer.drainReadyBlocks())
        XCTAssertEqual(out[9_599], 0.1)
        XCTAssertEqual(out[9_600], 0)
        XCTAssertEqual(out[9_600 + hole - 1], 0)
        XCTAssertEqual(out[9_600 + hole], 0.2, "audio after the hole must stay where it was")
    }

    func testFlushEmitsTheHoldBackAndAPartialBlock() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.pushMicrophone(constant(0.4, block + 100), reportedIndex: 0)
        XCTAssertTrue(mixer.drainReadyBlocks().isEmpty)
        let out = mixer.flush()
        XCTAssertEqual(samples(out).count, block + 100)
        XCTAssertEqual(out.last?.samples.count, 100)
        XCTAssertTrue(mixer.flush().isEmpty, "a second flush has nothing left")
    }

    func testSystemAudioBeforeTheMicrophoneStartsIsIgnored() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.pushSystem(constant(0.9, 5_000), reportedIndex: 0)
        mixer.pushMicrophone(constant(0.1, block + holdBack), reportedIndex: 10_000)
        let out = mixer.drainReadyBlocks()
        XCTAssertEqual(out.first?.startIndex, 10_000)
        XCTAssertEqual(samples(out), constant(0.1, block))
    }

    // MARK: - Crossfader and ducking

    func testTheMiddleIsThePlainSum() {
        XCTAssertEqual(AudioMix.gains(balance: 0).voice, 1)
        XCTAssertEqual(AudioMix.gains(balance: 0).system, 1)
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.mix = AudioMix(balance: 0)
        mixer.pushSystem(constant(0.5, block + holdBack), reportedIndex: 0)
        mixer.pushMicrophone(constant(0.25, block + holdBack), reportedIndex: 0)
        XCTAssertEqual(samples(mixer.drainReadyBlocks()), constant(0.75, block))
    }

    func testTheEndsSilenceTheOtherSide() {
        XCTAssertEqual(AudioMix.gains(balance: -1).system, 0)
        XCTAssertEqual(AudioMix.gains(balance: -1).voice, 1)
        XCTAssertEqual(AudioMix.gains(balance: 1).voice, 0)
        XCTAssertEqual(AudioMix.gains(balance: 1).system, 1)
        XCTAssertEqual(AudioMix.gains(balance: -0.5).system, 0.25, accuracy: 0.0001)
    }

    /// A fader moved mid-take ramps across the next block rather than jumping —
    /// and the block after it sits at the new level.
    func testMovingTheFaderRampsWithoutAJump() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.pushMicrophone(constant(0, block * 2 + holdBack), reportedIndex: 0)
        mixer.pushSystem(constant(0.8, block * 2 + holdBack), reportedIndex: 0)
        mixer.mix = AudioMix(balance: -1)
        let out = mixer.drainReadyBlocks()
        XCTAssertEqual(out.count, 2)
        let ramp = out[0].samples
        XCTAssertEqual(ramp[0], 0.8, accuracy: 0.01, "starts where the last block left off")
        XCTAssertEqual(ramp[block - 1], 0, accuracy: 0.0001, "arrives at the new level")
        for index in 1..<block { XCTAssertLessThanOrEqual(ramp[index], ramp[index - 1]) }
        XCTAssertEqual(out[1].samples, constant(0, block))
    }

    func testDuckingLowersTheMacWhileYouTalkAndReturnsAfterwards() {
        var ducker = Ducker()
        let speech = constant(0.1, block)     // −20 dBFS
        let silence = constant(0, block)
        var gain: Float = 1
        for _ in 0..<10 { gain = ducker.next(microphone: speech) }
        XCTAssertEqual(gain, Ducker.duckedGain, accuracy: 0.0001, "ducked while talking")

        // Held through a short pause between words.
        let holdBlocks = Int(Ducker.holdSeconds * Float(AudioMixerCore.sampleRate)) / block
        for _ in 0..<holdBlocks { gain = ducker.next(microphone: silence) }
        XCTAssertEqual(gain, Ducker.duckedGain, accuracy: 0.0001, "held between words")

        let releaseBlocks = Int(Ducker.releaseSeconds * Float(AudioMixerCore.sampleRate)) / block + 3
        for _ in 0..<releaseBlocks { gain = ducker.next(microphone: silence) }
        XCTAssertEqual(gain, 1, "back to full after a pause")
    }

    func testDuckingOnlyTouchesTheMac() {
        var mixer = AudioMixerCore(microphoneIsMaster: true)
        mixer.mix = AudioMix(balance: 0, ducksSystem: true)
        let frames = block * 12
        mixer.pushMicrophone(constant(0.1, frames + holdBack), reportedIndex: 0)
        mixer.pushSystem(constant(0.4, frames + holdBack), reportedIndex: 0)
        let last = mixer.drainReadyBlocks().last!.samples
        XCTAssertEqual(last[block - 1], 0.1 + 0.4 * Ducker.duckedGain, accuracy: 0.0001)
    }
}

final class SourceTimelineTests: XCTestCase {
    func testConsecutiveBuffersAreLaidEndToEnd() {
        var timeline = SourceTimeline()
        XCTAssertEqual(timeline.place(count: 1_024, reportedIndex: 0), 0)
        // Reported one sample late through rounding: still placed contiguously.
        XCTAssertEqual(timeline.place(count: 1_024, reportedIndex: 1_025), 1_024)
        XCTAssertEqual(timeline.place(count: 1_024, reportedIndex: 2_047), 2_048)
    }

    func testARealGapIsHonoured() {
        var timeline = SourceTimeline()
        _ = timeline.place(count: 1_024, reportedIndex: 0)
        XCTAssertEqual(timeline.place(count: 1_024, reportedIndex: 5_000), 5_000)
    }

    /// 2 ms of drift per minute, over ten minutes: placement never strays more
    /// than the tolerance from the timestamps, however long the take runs.
    func testDriftDoesNotAccumulate() {
        var timeline = SourceTimeline()
        let bufferFrames = 1_024
        let driftPerBuffer = 0.002 / 60 * (Double(bufferFrames) / 48_000) * 48_000
        var reported = 0.0
        var worst: Int64 = 0

        for _ in 0..<(10 * 60 * 48_000 / bufferFrames) {
            let reportedIndex = Int64(reported.rounded())
            let placed = timeline.place(count: bufferFrames, reportedIndex: reportedIndex)
            worst = max(worst, abs(placed - reportedIndex))
            reported += Double(bufferFrames) + driftPerBuffer
        }
        XCTAssertLessThanOrEqual(worst, SourceTimeline.tolerance)
    }
}
