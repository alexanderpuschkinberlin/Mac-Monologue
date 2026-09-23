import AVFoundation
import CoreMedia

/// Mixes the microphone with system audio into one mono 48 kHz track.
///
/// `AudioMixerCore` does the arithmetic and is tested on its own; this adds the
/// conversion from whatever each source delivers — a USB microphone at 44.1 kHz,
/// stereo system audio — into the one format the core works in.
///
/// Not thread-safe; confined to the capture output queue.
final class AudioMixer {
    private var core: AudioMixerCore
    private let microphoneConverter = PCMConverter()
    private let systemConverter = PCMConverter()

    init(microphoneIsMaster: Bool) {
        core = AudioMixerCore(microphoneIsMaster: microphoneIsMaster)
    }

    func pushMicrophone(_ sampleBuffer: CMSampleBuffer, takeTime: CMTime) {
        guard let samples = microphoneConverter.convert(sampleBuffer) else { return }
        core.pushMicrophone(samples, reportedIndex: Self.frameIndex(takeTime))
    }

    func pushSystem(_ sampleBuffer: CMSampleBuffer, takeTime: CMTime) {
        guard let samples = systemConverter.convert(sampleBuffer) else { return }
        core.pushSystem(samples, reportedIndex: Self.frameIndex(takeTime))
    }

    /// Mixed blocks ready to append, already timestamped in take time.
    func drainReady() -> [CMSampleBuffer] { Self.wrap(core.drainReadyBlocks()) }

    /// Everything still held, for the end of a take.
    func flush() -> [CMSampleBuffer] { Self.wrap(core.flush()) }

    private static func frameIndex(_ takeTime: CMTime) -> Int64 {
        Int64((takeTime.seconds * Double(AudioMixerCore.sampleRate)).rounded())
    }

    private static func wrap(_ blocks: [AudioMixerCore.Block]) -> [CMSampleBuffer] {
        blocks.compactMap { block in
            PCMSampleBuffer.make(
                samples: block.samples,
                presentationTime: CMTime(value: block.startIndex,
                                         timescale: CMTimeScale(AudioMixerCore.sampleRate))
            )
        }
    }
}

/// Converts one source's audio into mono Float32 at 48 kHz.
///
/// Built from the format the first buffer *actually* has, never the format that
/// was asked for — the microphone in particular arrives in whatever its hardware
/// does — and rebuilt if that ever changes.
final class PCMConverter {
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func convert(_ sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0,
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        input.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: input.mutableAudioBufferList
        ) == noErr else { return nil }

        if converter == nil || inputFormat != format {
            converter = AVAudioConverter(from: format, to: PCMSampleBuffer.format)
            // Stereo system audio folds into mono by mixing both channels, rather
            // than keeping only the left one.
            converter?.downmix = true
            inputFormat = format
        }
        guard let converter else { return nil }

        let ratio = PCMSampleBuffer.format.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: PCMSampleBuffer.format, frameCapacity: capacity)
        else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                // Keep the resampler's state for the next buffer rather than
                // flushing it: the stream continues.
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
