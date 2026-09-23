import Foundation

/// The arithmetic of mixing the microphone with system audio into one track.
///
/// Pure: samples in, blocks out, no AVFoundation — so every rule below is unit
/// tested without a device. `AudioMixer` wraps it with format conversion.
///
/// **One source is the master.** A block is emitted once the master has covered
/// it plus `holdBackFrames`, using whatever the other source has for that span and
/// silence for the rest. The hold-back gives late system audio time to land in its
/// own block; it delays when a block is written, never where it sits in the file.
/// The master is the microphone when there is one — a quiet Mac may send no system
/// audio at all, and waiting on it would stall the track.
struct AudioMixerCore {
    static let sampleRate = 48_000
    static let blockFrames = 1_024
    static let holdBackFrames: Int64 = 4_800          // 100 ms

    struct Block: Equatable {
        var startIndex: Int64
        var samples: [Float]
    }

    private(set) var microphone = TimedRingBuffer(capacity: sampleRate * 4)
    private(set) var system = TimedRingBuffer(capacity: sampleRate * 4)
    private var microphoneTimeline = SourceTimeline()
    private var systemTimeline = SourceTimeline()
    private var nextBlockIndex: Int64?

    let microphoneIsMaster: Bool

    init(microphoneIsMaster: Bool) {
        self.microphoneIsMaster = microphoneIsMaster
    }

    private var master: TimedRingBuffer { microphoneIsMaster ? microphone : system }

    mutating func pushMicrophone(_ samples: [Float], reportedIndex: Int64) {
        let start = microphoneTimeline.place(count: samples.count, reportedIndex: reportedIndex)
        microphone.write(samples, at: start)
    }

    mutating func pushSystem(_ samples: [Float], reportedIndex: Int64) {
        let start = systemTimeline.place(count: samples.count, reportedIndex: reportedIndex)
        system.write(samples, at: start)
    }

    /// Every whole block the master now covers, beyond the hold-back.
    mutating func drainReadyBlocks() -> [Block] {
        guard !master.isEmpty else { return [] }
        if nextBlockIndex == nil { nextBlockIndex = master.lowerBound }

        var blocks: [Block] = []
        while let start = nextBlockIndex,
              start + Int64(Self.blockFrames) + Self.holdBackFrames <= master.upperBound {
            blocks.append(mix(from: start, count: Self.blockFrames))
            nextBlockIndex = start + Int64(Self.blockFrames)
        }
        return blocks
    }

    /// Everything the master holds, hold-back included — for the end of a take.
    mutating func flush() -> [Block] {
        var blocks = drainReadyBlocks()
        guard !master.isEmpty else { return blocks }
        var start = nextBlockIndex ?? master.lowerBound
        while start < master.upperBound {
            let count = Int(min(Int64(Self.blockFrames), master.upperBound - start))
            blocks.append(mix(from: start, count: count))
            start += Int64(count)
        }
        nextBlockIndex = start
        return blocks
    }

    private func mix(from start: Int64, count: Int) -> Block {
        let mic = microphone.read(count: count, from: start)
        let sys = system.read(count: count, from: start)
        // Summed and hard-clamped. No ducking: attenuating the microphone would
        // make the level meter, which shows the microphone, lie.
        let samples = zip(mic, sys).map { min(1, max(-1, $0 + $1)) }
        return Block(startIndex: start, samples: samples)
    }
}

/// Keeps one source's samples contiguous.
///
/// Each buffer comes with a timestamp, but deriving every write position from it
/// independently lets rounding and converter latency leave one-sample gaps and
/// overlaps between consecutive buffers — clicks. So consecutive buffers are laid
/// end to end, and the timestamp is only obeyed when it disagrees by more than the
/// tolerance: a real gap, such as dropped buffers, is honoured, and slow clock
/// drift is corrected in bounded steps instead of accumulating.
struct SourceTimeline {
    static let tolerance: Int64 = 480                 // 10 ms at 48 kHz

    private var nextIndex: Int64?

    mutating func place(count: Int, reportedIndex: Int64) -> Int64 {
        let start: Int64
        if let next = nextIndex, abs(reportedIndex - next) <= Self.tolerance {
            start = next
        } else {
            start = reportedIndex
        }
        nextIndex = start + Int64(count)
        return start
    }
}
