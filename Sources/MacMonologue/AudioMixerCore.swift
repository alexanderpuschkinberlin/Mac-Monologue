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

    /// The crossfader and ducking, read for every block — so moving the fader
    /// mid-take changes the recording from the next block on.
    var mix = AudioMix()
    /// The gains the last block ended on; the next one ramps from there.
    private var voiceGain: Float = 1
    private var systemGain: Float = 1
    private var ducker = Ducker()

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

    private mutating func mix(from start: Int64, count: Int) -> Block {
        let mic = microphone.read(count: count, from: start)
        let sys = system.read(count: count, from: start)

        let fader = AudioMix.gains(balance: mix.balance)
        let duck = mix.ducksSystem ? ducker.next(microphone: mic) : ducker.reset()
        let voiceTarget = fader.voice
        let systemTarget = fader.system * duck
        // Each gain moves from where the last block left it to its new value
        // across this block: a fader moved or a duck setting in never jumps,
        // which would click. Standing still, both stay exactly 1 — the plain sum.
        let fromVoice = voiceGain, fromSystem = systemGain
        let steps = Float(count)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let t = Float(index + 1) / steps
            let voice = fromVoice + (voiceTarget - fromVoice) * t
            let system = fromSystem + (systemTarget - fromSystem) * t
            // Summed and hard-clamped.
            samples[index] = min(1, max(-1, mic[index] * voice + sys[index] * system))
        }
        voiceGain = voiceTarget
        systemGain = systemTarget
        return Block(startIndex: start, samples: samples)
    }
}

/// How loud each source goes into the mix: one crossfader between the voice
/// and the Mac's sound, and optional ducking of the Mac while you talk.
struct AudioMix: Equatable, Sendable {
    /// −1 is voice only, 0 both full, 1 Mac sound only.
    var balance: Float = 0
    var ducksSystem = false

    /// The side the fader moves towards stays at full; the other fades out along
    /// a square curve, which sounds even where a straight line would do little
    /// for most of the travel and then drop off at the end.
    static func gains(balance: Float) -> (voice: Float, system: Float) {
        let b = min(1, max(-1, balance))
        func fade(_ x: Float) -> Float { (1 - x) * (1 - x) }
        return (voice: b > 0 ? fade(b) : 1, system: b < 0 ? fade(-b) : 1)
    }

    /// The fader's gain in dB, for the meters; the floor for silence.
    static func decibels(_ gain: Float) -> Float {
        gain > 0 ? 20 * log10(gain) : AudioLevelMeter.floorDB
    }
}

/// Lowers the Mac's sound while the microphone hears speech, the way radio
/// does. Only the Mac is lowered: the voice, and the meter that shows it, stay
/// as they are.
///
/// Speech is a block whose microphone RMS is above `thresholdDB`. It pulls the
/// gain down within `attackSeconds`; once quiet for `holdSeconds`, the gain
/// comes back within `releaseSeconds`, so the gaps between words do not pump.
struct Ducker {
    static let thresholdDB: Float = -38
    static let duckedGain: Float = 0.25               // −12 dB
    static let attackSeconds: Float = 0.06
    static let holdSeconds: Float = 0.4
    static let releaseSeconds: Float = 0.6

    private(set) var gain: Float = 1
    private var quietFrames = Int.max / 2

    /// The gain at the end of this block of microphone samples.
    mutating func next(microphone: [Float]) -> Float {
        guard !microphone.isEmpty else { return gain }
        let rms = sqrt(microphone.reduce(0) { $0 + $1 * $1 } / Float(microphone.count))
        let rate = Float(AudioMixerCore.sampleRate)
        let frames = Float(microphone.count)
        if AudioLevelMeter.decibels(rms) > Self.thresholdDB {
            quietFrames = 0
            let step = (1 - Self.duckedGain) / (Self.attackSeconds * rate) * frames
            gain = max(Self.duckedGain, gain - step)
        } else {
            quietFrames += microphone.count
            if Float(quietFrames) > Self.holdSeconds * rate {
                let step = (1 - Self.duckedGain) / (Self.releaseSeconds * rate) * frames
                gain = min(1, gain + step)
            }
        }
        return gain
    }

    /// Off: back to full, through the mixer's ramp.
    mutating func reset() -> Float {
        gain = 1
        quietFrames = Int.max / 2
        return gain
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
