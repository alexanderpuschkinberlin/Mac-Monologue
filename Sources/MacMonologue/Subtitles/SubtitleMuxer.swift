import AVFoundation
import CoreMedia
import Foundation

/// Adds subtitle tracks to a finished take, one per language, switchable in any
/// player that has a subtitles menu — QuickTime, VLC, IINA.
///
/// The picture and sound are copied as they are, sample for sample, into a new
/// file next to the original, which then replaces it in one step. Nothing is
/// re-encoded, and a cancelled or failed run leaves the original untouched.
///
/// Subtitles are 3GPP timed text (`tx3g`), the kind MP4 carries.
final class SubtitleMuxer: @unchecked Sendable {
    enum MuxError: LocalizedError {
        case cannotRead(String)
        case cannotWrite(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .cannotRead(let detail): "The video could not be read: \(detail)"
            case .cannotWrite(let detail): "The subtitles could not be added: \(detail)"
            case .cancelled: "Cancelled."
            }
        }
    }

    /// All reading and writing happens here, one callback at a time.
    private let queue = DispatchQueue(label: "io.github.alexanderpuschkinberlin.mac-monologue.subtitle-muxer")
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var isCancelled = false

    /// Replaces `video` with a copy that has `tracks` as subtitles. `progress`
    /// runs from 0 to 1 by how much of the picture has been copied.
    func addSubtitles(_ tracks: [(language: SubtitleLanguage, cues: [SubtitleCue])], to video: URL,
                      progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration)
        let sourceTracks = try await asset.load(.tracks).filter { $0.mediaType == .video || $0.mediaType == .audio }

        let temporary = video.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }

        try await withTaskCancellationHandler {
            try await copy(sourceTracks, of: asset, duration: duration, adding: tracks,
                           to: temporary, progress: progress)
        } onCancel: {
            self.cancel()
        }
        try Task.checkCancellation()
        _ = try FileManager.default.replaceItemAt(video, withItemAt: temporary)
    }

    func cancel() {
        queue.async {
            self.isCancelled = true
            self.reader?.cancelReading()
            self.writer?.cancelWriting()
        }
    }

    // MARK: - Copying

    private final class Lane {
        let input: AVAssetWriterInput
        var next: () -> CMSampleBuffer?
        var isDone = false
        init(input: AVAssetWriterInput, next: @escaping () -> CMSampleBuffer?) {
            self.input = input
            self.next = next
        }
    }

    private func copy(_ sourceTracks: [AVAssetTrack], of asset: AVAsset, duration: CMTime,
                      adding subtitles: [(language: SubtitleLanguage, cues: [SubtitleCue])],
                      to output: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        } catch {
            throw MuxError.cannotRead(error.localizedDescription)
        }

        var lanes: [Lane] = []
        var videoOutput: AVAssetReaderTrackOutput?
        for track in sourceTracks {
            let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            trackOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(trackOutput) else { throw MuxError.cannotRead("track \(track.trackID)") }
            reader.add(trackOutput)

            let format = try await track.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            input.transform = try await track.load(.preferredTransform)
            if let code = try await track.load(.languageCode) { input.languageCode = code }
            guard writer.canAdd(input) else { throw MuxError.cannotWrite("\(track.mediaType.rawValue) track") }
            writer.add(input)

            if track.mediaType == .video, videoOutput == nil { videoOutput = trackOutput }
            let isVideo = track.mediaType == .video
            lanes.append(Lane(input: input) {
                guard let sample = trackOutput.copyNextSampleBuffer() else { return nil }
                if isVideo, duration.seconds > 0 {
                    progress(min(1, CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration.seconds))
                }
                return sample
            })
        }

        for subtitle in subtitles {
            let format = try Self.textFormatDescription()
            let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            input.languageCode = subtitle.language.threeLetterCode
            input.extendedLanguageTag = subtitle.language.rawValue
            guard writer.canAdd(input) else { throw MuxError.cannotWrite("subtitle track") }
            writer.add(input)
            var samples = try Self.samples(for: subtitle.cues, until: duration, format: format)[...]
            lanes.append(Lane(input: input) { samples.popFirst() })
        }

        guard reader.startReading() else {
            throw MuxError.cannotRead(reader.error?.localizedDescription ?? "unknown")
        }
        guard writer.startWriting() else {
            throw MuxError.cannotWrite(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        queue.sync {
            self.reader = reader
            self.writer = writer
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            for lane in lanes {
                group.enter()
                lane.input.requestMediaDataWhenReady(on: queue) {
                    guard !lane.isDone else { return }
                    while lane.input.isReadyForMoreMediaData {
                        guard !self.isCancelled, let sample = lane.next() else {
                            lane.isDone = true
                            lane.input.markAsFinished()
                            group.leave()
                            return
                        }
                        if !lane.input.append(sample) {
                            lane.isDone = true
                            group.leave()
                            return
                        }
                    }
                }
            }
            group.notify(queue: queue) {
                if self.isCancelled {
                    writer.cancelWriting()
                    continuation.resume(throwing: MuxError.cancelled)
                    return
                }
                if reader.status == .failed || writer.status == .failed {
                    writer.cancelWriting()
                    let detail = (writer.error ?? reader.error)?.localizedDescription ?? "unknown"
                    continuation.resume(throwing: MuxError.cannotWrite(detail))
                    return
                }
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: MuxError.cannotWrite(
                            writer.error?.localizedDescription ?? "unknown"))
                    }
                }
            }
        }
        progress(1)
    }

    // MARK: - Timed text

    /// Subtitle samples back to back from zero to the end of the video: each cue,
    /// and an empty sample in every gap, since a timed-text track has no holes.
    static func samples(for cues: [SubtitleCue], until duration: CMTime,
                        format: CMFormatDescription) throws -> [CMSampleBuffer] {
        let timescale: CMTimeScale = 1000
        func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: timescale) }

        var samples: [CMSampleBuffer] = []
        var cursor = CMTime.zero
        let end = CMTimeConvertScale(duration, timescale: timescale, method: .roundHalfAwayFromZero)
        for cue in cues.sorted(by: { $0.start < $1.start }) {
            let start = max(time(cue.start), cursor)
            let stop = min(time(cue.end), end)
            guard stop > start else { continue }
            if start > cursor { samples.append(try sample("", from: cursor, to: start, format: format)) }
            samples.append(try sample(cue.text, from: start, to: stop, format: format))
            cursor = stop
        }
        if end > cursor { samples.append(try sample("", from: cursor, to: end, format: format)) }
        return samples
    }

    /// A tx3g sample: the UTF-8 text behind a 16-bit big-endian length.
    static func sample(_ text: String, from start: CMTime, to end: CMTime,
                       format: CMFormatDescription) throws -> CMSampleBuffer {
        let utf8 = Array(text.utf8)
        var bytes = [UInt8(utf8.count >> 8 & 0xFF), UInt8(utf8.count & 0xFF)] + utf8

        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: bytes.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard status == noErr, let block else { throw MuxError.cannotWrite("text block (\(status))") }
        status = CMBlockBufferReplaceDataBytes(with: &bytes, blockBuffer: block, offsetIntoDestination: 0,
                                               dataLength: bytes.count)
        guard status == noErr else { throw MuxError.cannotWrite("text bytes (\(status))") }

        var timing = CMSampleTimingInfo(duration: end - start, presentationTimeStamp: start,
                                        decodeTimeStamp: .invalid)
        var size = bytes.count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw MuxError.cannotWrite("text sample (\(status))") }
        return sample
    }

    /// The tx3g sample entry, per 3GPP TS 26.245: white text, centred at the
    /// bottom, on no background — players draw their own subtitle style anyway.
    static func textFormatDescription() throws -> CMFormatDescription {
        var data: [UInt8] = []
        func u8(_ value: UInt8) { data.append(value) }
        func u16(_ value: UInt16) { data += [UInt8(value >> 8), UInt8(value & 0xFF)] }
        func u32(_ value: UInt32) { data += [UInt8(value >> 24), UInt8(value >> 16 & 0xFF),
                                             UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
        let fontName = Array("Sans-Serif".utf8)

        u32(0)                                  // size, filled in below
        data += Array("tx3g".utf8)
        data += [0, 0, 0, 0, 0, 0]              // reserved
        u16(1)                                  // data reference index
        u32(0)                                  // display flags
        u8(1)                                   // horizontal justification: centre
        u8(0xFF)                                // vertical justification: bottom (-1)
        data += [0, 0, 0, 0]                    // background: transparent
        u16(0); u16(0); u16(0); u16(0)          // default text box: the whole frame
        u16(0); u16(0)                          // style record: characters 0…0
        u16(1)                                  // font ID
        u8(0)                                   // face: plain
        u8(18)                                  // font size
        data += [0xFF, 0xFF, 0xFF, 0xFF]        // text colour: white
        u32(UInt32(8 + 2 + 2 + 1 + fontName.count))
        data += Array("ftab".utf8)
        u16(1)                                  // one font
        u16(1)                                  // font ID
        u8(UInt8(fontName.count))
        data += fontName
        let size = UInt32(data.count)
        data.replaceSubrange(0..<4, with: [UInt8(size >> 24), UInt8(size >> 16 & 0xFF),
                                           UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)])

        var description: CMFormatDescription?
        let status = data.withUnsafeBufferPointer { buffer in
            CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(
                allocator: kCFAllocatorDefault, bigEndianTextDescriptionData: buffer.baseAddress!,
                size: buffer.count, flavor: nil, mediaType: kCMMediaType_Subtitle,
                formatDescriptionOut: &description)
        }
        guard status == noErr, let description else {
            throw MuxError.cannotWrite("text format (\(status))")
        }
        return description
    }
}
