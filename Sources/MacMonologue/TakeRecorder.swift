import AVFoundation
import Foundation

/// Writes a take to disk, with pause and resume.
///
/// `AVCaptureMovieFileOutput` would be three lines, but it has no pause API at
/// all — so the sample buffers come here instead and every timestamp is ours to
/// control. Pause becomes arithmetic: `TakeClock` subtracts the paused intervals
/// and one continuous file comes out.
///
/// All state is confined to `queue`, which is also the queue `CaptureRouter`
/// delivers on. The class is `@unchecked Sendable` on that basis.
final class TakeRecorder: @unchecked Sendable {
    /// Which writer input a buffer belongs to. Explicit rather than inferred from
    /// the delivering `AVCaptureOutput`: a composited frame or a mixed audio block
    /// has no capture output behind it.
    enum Track: Sendable {
        case video
        case audio
    }

    enum Status: Equatable {
        case idle
        case recording
        case paused
        case finishing
    }

    struct Configuration {
        var width: Int
        var height: Int
        var frameRate: Double
        var audioSettings: [String: Any]?
        var averageBitRate: Int = TakeRecorder.cameraBitRate
    }

    /// 10 Mbps HEVC at 1080p30. A webcam's sensor noise is what eats bitrate, and
    /// a few wasted megabytes beat discovering grain artifacts after the fact.
    static let cameraBitRate = 10_000_000

    /// 12 Mbps at the 2560-px screen canvas: a fixed rate, chosen over
    /// quality-based control so a take's size stays predictable.
    static let screenBitRate = 12_000_000

    private let queue: DispatchQueue
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var clock = TakeClock()
    private var sourceClock: CMClock?
    private var sessionStarted = false
    private var temporaryURL: URL?
    private var hasAudio = false
    /// AVAssetWriter requires strictly increasing presentation times per input,
    /// and rejects the whole take otherwise.
    private var lastVideoTime: CMTime?
    private var lastAudioTime: CMTime?

    private(set) var status: Status = .idle

    /// Callbacks hop to the main actor themselves; they are called on `queue`.
    var onStatusChange: (@Sendable (Status) -> Void)?
    var onDurationChange: (@Sendable (Double) -> Void)?
    var onFailure: (@Sendable (String) -> Void)?
    /// Called on `queue` at the start of `finish`, while the take is still
    /// writable — the last chance to hand over audio that was being held back.
    var onWillFinish: (() -> Void)?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    // MARK: - Destination

    static var recordingsDirectory: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        return movies.appendingPathComponent("Monologue", isDirectory: true)
    }

    /// `Monologue-yyyy-MM-dd-HHmmss.mp4`, matching omacom/monologue's convention.
    static func filename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Monologue-\(formatter.string(from: date)).mp4"
    }

    // MARK: - Control

    func start(configuration: Configuration, sourceClock: CMClock?) {
        queue.async { [self] in
            guard status == .idle else { return }

            // Record to a temp file and move on Finish, so a crash or a discard
            // never leaves a stray partial file in the folder the user looks at.
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")

            do {
                let writer = try AVAssetWriter(outputURL: temp, fileType: .mp4)
                // Puts the moov atom at the front — what the original shells out
                // to ffmpeg for with `-movflags +faststart`.
                writer.shouldOptimizeForNetworkUse = true

                let videoInput = AVAssetWriterInput(
                    mediaType: .video,
                    outputSettings: Self.videoSettings(for: configuration)
                )
                videoInput.expectsMediaDataInRealTime = true
                guard writer.canAdd(videoInput) else {
                    throw RecorderError.cannotAddInput
                }
                writer.add(videoInput)

                var audioInput: AVAssetWriterInput?
                if let audioSettings = configuration.audioSettings {
                    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                    input.expectsMediaDataInRealTime = true
                    if writer.canAdd(input) {
                        writer.add(input)
                        audioInput = input
                    }
                }

                guard writer.startWriting() else {
                    throw writer.error ?? RecorderError.cannotStartWriting
                }

                self.writer = writer
                self.videoInput = videoInput
                self.audioInput = audioInput
                self.hasAudio = audioInput != nil
                self.temporaryURL = temp
                self.sourceClock = sourceClock
                self.clock = TakeClock()
                self.sessionStarted = false
                self.setStatus(.recording)
            } catch {
                cleanUp()
                onFailure?("Could not start recording: \(error.localizedDescription)")
            }
        }
    }

    func pause() {
        queue.async { [self] in
            guard status == .recording else { return }
            clock.pause(at: now())
            setStatus(.paused)
        }
    }

    func resume() {
        queue.async { [self] in
            guard status == .paused else { return }
            clock.resume(at: now())
            setStatus(.recording)
        }
    }

    /// Finishes and moves the file into `~/Movies/Monologue`.
    func finish(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        queue.async { [self] in
            guard status == .recording || status == .paused else { return }
            onWillFinish?()
            if status == .recording { clock.pause(at: now()) }
            setStatus(.finishing)

            videoInput?.markAsFinished()
            audioInput?.markAsFinished()

            guard let writer, let temporaryURL else {
                completion(.failure(RecorderError.notRecording))
                return
            }

            writer.finishWriting { [self] in
                queue.async { [self] in
                    defer { cleanUp() }

                    if writer.status == .failed {
                        completion(.failure(writer.error ?? RecorderError.writeFailed))
                        return
                    }
                    do {
                        let destination = try Self.moveIntoRecordings(temporaryURL)
                        completion(.success(destination))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    /// Abandons the take. Nothing has reached `~/Movies` yet, so this is a
    /// temp-file delete rather than something the user can miss.
    func discard() {
        queue.async { [self] in
            guard status != .idle else { return }
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            writer?.cancelWriting()
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
            cleanUp()
        }
    }

    // MARK: - Internals

    private func now() -> CMTime {
        guard let sourceClock else { return CMClockGetTime(CMClockGetHostTimeClock()) }
        return CMClockGetTime(sourceClock)
    }

    private func setStatus(_ new: Status) {
        status = new
        onStatusChange?(new)
    }

    private func cleanUp() {
        writer = nil
        videoInput = nil
        audioInput = nil
        temporaryURL = nil
        sourceClock = nil
        sessionStarted = false
        lastVideoTime = nil
        lastAudioTime = nil
        clock = TakeClock()
        setStatus(.idle)
    }

    private static func moveIntoRecordings(_ temporaryURL: URL) throws -> URL {
        let directory = recordingsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var destination = directory.appendingPathComponent(filename())
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let name = filename().replacingOccurrences(of: ".mp4", with: "-\(suffix).mp4")
            destination = directory.appendingPathComponent(name)
            suffix += 1
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private static func videoSettings(for configuration: Configuration) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: configuration.averageBitRate,
                AVVideoExpectedSourceFrameRateKey: Int(configuration.frameRate),
            ],
        ]
    }

    /// AVFoundation's `localizedDescription` is usually the useless
    /// "The operation could not be completed" — the actual cause lives in the
    /// failure reason and the underlying error.
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [nsError.localizedDescription]
        if let reason = nsError.localizedFailureReason { parts.append(reason) }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("(\(underlying.domain) \(underlying.code))")
        }
        parts.append("[\(nsError.domain) \(nsError.code)]")
        return parts.joined(separator: " ")
    }

    enum RecorderError: LocalizedError {
        case cannotAddInput
        case cannotStartWriting
        case notRecording
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .cannotAddInput: "The encoder rejected this camera format."
            case .cannotStartWriting: "The file could not be opened for writing."
            case .notRecording: "There is no take in progress."
            case .writeFailed: "Writing the file failed."
            }
        }
    }
}

// MARK: - Sample buffers

extension TakeRecorder {
    /// Whether a take is currently being written. Call on `queue`.
    var isWriting: Bool {
        (status == .recording || status == .paused) && writer?.status == .writing
    }

    /// The capture clock's current time — for frames that have no timestamp of
    /// their own, such as the screen shown on its own while the camera is gone.
    /// Call on `queue`.
    func currentCaptureTime() -> CMTime { now() }

    /// The clock the take's timestamps are in. Call on `queue`.
    func currentSourceClock() -> CMClock { sourceClock ?? CMClockGetHostTimeClock() }

    /// Maps a capture timestamp onto take time, or nil while paused or before the
    /// take began. Call on `queue`.
    ///
    /// Exposed so a second audio source can be placed on the same timeline as the
    /// microphone before it is mixed — the pause arithmetic stays in one place.
    func takeTime(for captureTime: CMTime) -> CMTime? {
        guard sessionStarted, status == .recording else { return nil }
        return clock.takeTime(for: captureTime)
    }

    /// Appends one buffer to the take. Must be called on `queue`.
    func append(_ sampleBuffer: CMSampleBuffer, to track: Track) {
        let isVideo = track == .video

        guard status == .recording, let writer, writer.status == .writing else { return }

        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !sessionStarted {
            // Take time starts at zero on the first video frame; audio arriving
            // before it is dropped rather than starting the session on a sound.
            guard isVideo else { return }
            clock.resume(at: presentation)
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
        }

        // nil means the sample arrived while paused: buffers keep coming from the
        // session, and writing them would reinstate the dead air pause removes.
        guard let takeTime = clock.takeTime(for: presentation) else { return }

        let lastTime = isVideo ? lastVideoTime : lastAudioTime
        if let lastTime, takeTime <= lastTime { return }

        let input = isVideo ? videoInput : audioInput
        guard let input, input.isReadyForMoreMediaData else { return }
        guard let retimed = Self.retime(sampleBuffer, to: takeTime) else { return }

        if !input.append(retimed) {
            let reason = writer.error.map(Self.describe) ?? "the encoder rejected a frame"
            onFailure?("Recording stopped: \(reason)")
            discard()
            return
        }

        if isVideo {
            lastVideoTime = takeTime
            onDurationChange?(takeTime.seconds)
        } else {
            lastAudioTime = takeTime
        }
    }

    /// Appends a buffer whose timestamp is already take time — a mixed audio
    /// block built downstream of `takeTime(for:)`. Must be called on `queue`.
    func appendInTakeTime(_ sampleBuffer: CMSampleBuffer, to track: Track) {
        // Paused is fine too: these are samples from before the pause, released late.
        guard status == .recording || status == .paused, sessionStarted,
              let writer, writer.status == .writing else { return }

        let takeTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let lastTime = track == .video ? lastVideoTime : lastAudioTime
        if let lastTime, takeTime <= lastTime { return }

        let input = track == .video ? videoInput : audioInput
        guard let input, input.isReadyForMoreMediaData else { return }

        if !input.append(sampleBuffer) {
            let reason = writer.error.map(Self.describe) ?? "the encoder rejected a sample"
            onFailure?("Recording stopped: \(reason)")
            discard()
            return
        }

        if track == .video { lastVideoTime = takeTime } else { lastAudioTime = takeTime }
    }

    private static func retime(_ sampleBuffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var retimed: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimed
        )
        return status == noErr ? retimed : nil
    }
}
