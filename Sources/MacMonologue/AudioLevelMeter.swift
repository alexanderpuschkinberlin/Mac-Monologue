import AVFoundation
import Foundation

/// RMS and peak level in dBFS, with peak-hold and a clipping flag.
///
/// Live from launch and while paused, never monitored through the speakers.
/// It is the one piece of UI that tells you the take is going to be fine
/// *before* you spend three minutes on it.
///
/// Pure arithmetic over a sample buffer: no session, no writer, no state beyond
/// the held peak. Touched only on the capture output queue.
final class AudioLevelMeter {
    /// Bottom of the scale, matching the −60…0 dB readout in the UI.
    static let floorDB: Float = -60
    /// A sample at or above this counts as clipping.
    static let clipThresholdDB: Float = -0.1

    /// Peak-hold decay, in dB per second.
    private let peakDecayRate: Float = 12

    private(set) var level: Float = floorDB
    private(set) var peak: Float = floorDB
    private(set) var isClipping = false

    private var lastUpdate: CFTimeInterval?
    private var clipUntil: CFTimeInterval = 0

    func reset() {
        level = Self.floorDB
        peak = Self.floorDB
        isClipping = false
        lastUpdate = nil
    }

    /// Returns true when the reading changed enough to be worth publishing.
    @discardableResult
    func consume(_ sampleBuffer: CMSampleBuffer, now: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        guard let (rms, absolutePeak) = Self.measure(sampleBuffer) else { return false }

        let rmsDB = Self.decibels(rms)
        let peakDB = Self.decibels(absolutePeak)

        // Decay the held peak rather than snapping it down, so a transient stays
        // readable for a moment instead of flashing past.
        let elapsed = Float(now - (lastUpdate ?? now))
        lastUpdate = now
        let decayed = max(Self.floorDB, peak - peakDecayRate * elapsed)

        level = rmsDB
        peak = max(decayed, peakDB)

        // Hold the clip indicator briefly; a single clipped sample is otherwise
        // invisible at any sane refresh rate.
        if peakDB >= Self.clipThresholdDB { clipUntil = now + 1.5 }
        isClipping = now < clipUntil

        return true
    }

    static func decibels(_ amplitude: Float) -> Float {
        guard amplitude > 0 else { return floorDB }
        return max(floorDB, 20 * log10(amplitude))
    }

    /// Normalised 0…1 position on the −60…0 scale.
    static func fraction(forDB value: Float) -> Float {
        guard value > floorDB else { return 0 }
        return min(1, (value - floorDB) / -floorDB)
    }

    // MARK: - Measurement

    /// Returns (rms, peak) as linear amplitudes, or nil if the buffer is not PCM.
    private static func measure(_ sampleBuffer: CMSampleBuffer) -> (Float, Float)? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        else { return nil }

        // Sized for as many buffers as the format has: ScreenCaptureKit delivers
        // system audio as non-interleaved stereo, one buffer per channel, which a
        // single-buffer list cannot hold.
        var sizeNeeded = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: nil
        ) == noErr, sizeNeeded > 0 else { return nil }

        let rawList = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded,
                                                       alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawList.deallocate() }
        let listPointer = rawList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: listPointer,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        var sumOfSquares: Float = 0
        var peak: Float = 0
        var count = 0

        for buffer in UnsafeMutableAudioBufferListPointer(listPointer) {
            guard let data = buffer.mData else { continue }
            let byteCount = Int(buffer.mDataByteSize)
            if isFloat {
                let length = byteCount / MemoryLayout<Float>.size
                let samples = data.bindMemory(to: Float.self, capacity: length)
                for index in 0..<length {
                    let value = abs(samples[index])
                    sumOfSquares += value * value
                    peak = max(peak, value)
                }
                count += length
            } else {
                let length = byteCount / MemoryLayout<Int16>.size
                let samples = data.bindMemory(to: Int16.self, capacity: length)
                for index in 0..<length {
                    let value = abs(Float(samples[index])) / Float(Int16.max)
                    sumOfSquares += value * value
                    peak = max(peak, value)
                }
                count += length
            }
        }

        guard count > 0 else { return nil }
        return (sqrt(sumOfSquares / Float(count)), peak)
    }
}
