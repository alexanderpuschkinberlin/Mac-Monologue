import AVFoundation
import XCTest
@testable import Mac_Monologue

final class AudioLevelMeterTests: XCTestCase {
    /// System audio from ScreenCaptureKit is non-interleaved stereo: one buffer
    /// per channel. The meter has to read both.
    func testNonInterleavedStereoIsMeasured() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        XCTAssertFalse(format.isInterleaved)
        let frames: AVAudioFrameCount = 480
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        pcm.frameLength = frames
        for channel in 0..<2 {
            let data = try XCTUnwrap(pcm.floatChannelData?[channel])
            for index in 0..<Int(frames) { data[index] = 0.5 }
        }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        XCTAssertEqual(CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false,
                                            makeDataReadyCallback: nil, refcon: nil,
                                            formatDescription: format.formatDescription,
                                            sampleCount: CMItemCount(frames), sampleTimingEntryCount: 1,
                                            sampleTimingArray: &timing, sampleSizeEntryCount: 0,
                                            sampleSizeArray: nil, sampleBufferOut: &sampleBuffer), noErr)
        let buffer = try XCTUnwrap(sampleBuffer)
        XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(
            buffer, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            bufferList: pcm.audioBufferList), noErr)

        let meter = AudioLevelMeter()
        XCTAssertTrue(meter.consume(buffer))
        XCTAssertEqual(meter.level, AudioLevelMeter.decibels(0.5), accuracy: 0.01)
    }
}
