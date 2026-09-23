import AVFoundation
import XCTest
@testable import Mac_Monologue

final class SubtitleMuxerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubtitleMuxerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Two seconds of grey picture and a quiet tone, as HEVC and AAC in an MP4 —
    /// the shape of a real take.
    private func makeTake(seconds: Int = 2) async throws -> URL {
        let url = directory.appendingPathComponent("take.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 320, AVVideoHeightKey: 180,
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
        ])
        video.expectsMediaDataInRealTime = true
        audio.expectsMediaDataInRealTime = true
        writer.add(video)
        writer.add(audio)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let pool = try XCTUnwrap(PixelBufferPool(width: 320, height: 180))
        for frame in 0..<(seconds * 30) {
            let time = CMTime(value: CMTimeValue(frame), timescale: 30)
            while !video.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            let pixels = try XCTUnwrap(pool.makeBuffer())
            video.append(try XCTUnwrap(ImageSampleBuffer.make(imageBuffer: pixels, presentationTime: time,
                                                              duration: CMTime(value: 1, timescale: 30))))
            let block = 1600
            let samples = (0..<block).map { Float(sin(Double(frame * block + $0) * 0.05)) * 0.1 }
            while !audio.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            audio.append(try XCTUnwrap(PCMSampleBuffer.make(
                samples: samples, presentationTime: CMTime(value: CMTimeValue(frame * block), timescale: 48_000))))
        }
        video.markAsFinished()
        audio.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error.map { "\($0)" } ?? "")
        return url
    }

    private let cues = [
        (language: SubtitleLanguage.german, cues: [SubtitleCue(start: 0.2, end: 1.0, text: "Hallo"),
                                                    SubtitleCue(start: 1.2, end: 1.8, text: "zwei\nZeilen")]),
        (language: SubtitleLanguage.english, cues: [SubtitleCue(start: 0.2, end: 1.0, text: "Hello")]),
    ]

    func testAddsASwitchableTrackPerLanguageAndKeepsPictureAndSound() async throws {
        let take = try await makeTake()
        let before = AVURLAsset(url: take)
        let videoBefore = try await before.loadTracks(withMediaType: .video).first!
        let sampleCountBefore = try await sampleCount(of: videoBefore, in: before)
        let durationBefore = try await before.load(.duration)

        try await SubtitleMuxer().addSubtitles(cues, to: take) { _ in }

        let after = AVURLAsset(url: take)
        let subtitles = try await after.loadTracks(withMediaType: .subtitle)
        XCTAssertEqual(subtitles.count, 2)
        let languages = try await subtitles.asyncMap { try await $0.load(.extendedLanguageTag) }
        XCTAssertEqual(Set(languages.compactMap { $0 }), ["de", "en"])

        let videoAfter = try await after.loadTracks(withMediaType: .video)
        let audioAfter = try await after.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoAfter.count, 1)
        XCTAssertEqual(audioAfter.count, 1)
        let sampleCountAfter = try await sampleCount(of: videoAfter[0], in: after)
        XCTAssertEqual(sampleCountAfter, sampleCountBefore, "every frame copied, none re-encoded or lost")
        let durationAfter = try await after.load(.duration)
        XCTAssertEqual(durationAfter.seconds, durationBefore.seconds, accuracy: 0.05)

        let texts = try await subtitleTexts(of: subtitles.first { _ in true }!, in: after)
        XCTAssertTrue(texts.contains("Hallo") || texts.contains("Hello"), "\(texts)")
    }

    func testTheTextComesBackAsWritten() async throws {
        let take = try await makeTake()
        try await SubtitleMuxer().addSubtitles([cues[0]], to: take) { _ in }
        let asset = AVURLAsset(url: take)
        let track = try await asset.loadTracks(withMediaType: .subtitle).first!
        let texts = try await subtitleTexts(of: track, in: asset).filter { !$0.isEmpty }
        XCTAssertEqual(texts, ["Hallo", "zwei\nZeilen"])
    }

    func testCancellingLeavesTheTakeAsItWas() async throws {
        let take = try await makeTake(seconds: 4)
        let original = try Data(contentsOf: take)
        let muxer = SubtitleMuxer()
        muxer.cancel()
        do {
            try await muxer.addSubtitles(cues, to: take) { _ in }
            XCTFail("a cancelled run must not finish")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: take), original, "byte for byte")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["take.mp4"], "no half-written file left behind")
    }

    func testGapsAreFilledSoTheTrackHasNoHoles() throws {
        let format = try SubtitleMuxer.textFormatDescription()
        let samples = try SubtitleMuxer.samples(
            for: [SubtitleCue(start: 1, end: 2, text: "a"), SubtitleCue(start: 3, end: 4, text: "b")],
            until: CMTime(seconds: 5, preferredTimescale: 1000), format: format)
        XCTAssertEqual(samples.count, 5, "gap, a, gap, b, gap")
        var cursor = CMTime.zero
        for sample in samples {
            XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample), cursor)
            cursor = cursor + CMSampleBufferGetDuration(sample)
        }
        XCTAssertEqual(cursor.seconds, 5, accuracy: 0.001)
    }

    // MARK: - Reading back

    private func sampleCount(of track: AVAssetTrack, in asset: AVAsset) async throws -> Int {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            count += CMSampleBufferGetNumSamples(sample)
        }
        return count
    }

    private func subtitleTexts(of track: AVAssetTrack, in asset: AVAsset) async throws -> [String] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var texts: [String] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var data = Data(count: CMBlockBufferGetDataLength(block))
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count,
                                                                         destination: $0.baseAddress!) }
            guard data.count >= 2 else { continue }
            let length = Int(data[0]) << 8 | Int(data[1])
            texts.append(String(decoding: data.dropFirst(2).prefix(length), as: UTF8.self))
        }
        return texts
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
