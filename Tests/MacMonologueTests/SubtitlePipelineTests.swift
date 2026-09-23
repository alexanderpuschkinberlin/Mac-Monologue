import AVFoundation
import XCTest
@testable import Mac_Monologue

/// The whole chain on this Mac's own speech recognition and translation: a take
/// with German speech in, a take with German and English subtitles out.
///
/// Skipped where the language tools are not installed — it proves the chain
/// works, not that a test machine has downloaded anything.
final class SubtitlePipelineTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubtitlePipelineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testGermanSpeechBecomesGermanAndEnglishSubtitles() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Subtitles need macOS 26") }
        guard await SubtitleAssets.readiness(spoken: .german, target: .english) == .ready else {
            throw XCTSkip("German speech recognition or German→English translation is not installed")
        }

        let take = try await makeTake(saying: "Hallo und herzlich willkommen. "
                                      + "Heute zeige ich euch, wie die neue Quartalsplanung funktioniert.")

        let words = try await SubtitleTranscriber.words(in: take, language: .german) { _ in }
        let said = words.map(\.text).joined(separator: " ")
        XCTAssertTrue(said.localizedCaseInsensitiveContains("willkommen"), said)
        XCTAssertTrue(said.localizedCaseInsensitiveContains("Quartalsplanung"), said)
        XCTAssertEqual(words.map(\.start), words.map(\.start).sorted(), "words in the order they were said")

        let cues = SubtitleSegmenter.cues(from: words)
        XCTAssertFalse(cues.isEmpty)
        let english = try await SubtitleTranslator.translate(cues, from: .german, to: .english) { _ in }
        XCTAssertEqual(english.map(\.start), cues.map(\.start), "translations keep their times")
        XCTAssertTrue(english.map(\.text).joined(separator: " ").localizedCaseInsensitiveContains("welcome"),
                      english.map(\.text).joined(separator: " | "))

        try await SubtitleMuxer().addSubtitles([(.german, cues), (.english, english)], to: take) { _ in }
        let subtitleTracks = try await AVURLAsset(url: take).loadTracks(withMediaType: .subtitle)
        XCTAssertEqual(subtitleTracks.count, 2)
    }

    /// A few seconds of picture with `text` spoken over it by a German system voice.
    private func makeTake(saying text: String) async throws -> URL {
        let speech = directory.appendingPathComponent("speech.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Anna", "-o", speech.path, text]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { throw XCTSkip("The German voice Anna is not installed") }

        let audioAsset = AVURLAsset(url: speech)
        let audioDuration = try await audioAsset.load(.duration)
        let seconds = Int(audioDuration.seconds.rounded(.up)) + 1

        // Picture first, on its own.
        let picture = directory.appendingPathComponent("picture.mp4")
        let writer = try AVAssetWriter(outputURL: picture, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 320, AVVideoHeightKey: 180,
        ])
        writer.add(video)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(PixelBufferPool(width: 320, height: 180))
        for frame in 0..<(seconds * 30) {
            while !video.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            let pixels = try XCTUnwrap(pool.makeBuffer())
            video.append(try XCTUnwrap(ImageSampleBuffer.make(
                imageBuffer: pixels, presentationTime: CMTime(value: CMTimeValue(frame), timescale: 30),
                duration: CMTime(value: 1, timescale: 30))))
        }
        video.markAsFinished()
        await writer.finishWriting()

        // Then picture and speech together, the sound as AAC like a real take.
        let composition = AVMutableComposition()
        let pictureAsset = AVURLAsset(url: picture)
        let pictureTracks = try await pictureAsset.loadTracks(withMediaType: .video)
        let pictureTrack = try XCTUnwrap(pictureTracks.first)
        let pictureRange = try await pictureTrack.load(.timeRange)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(pictureRange, of: pictureTrack, at: .zero)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let audioTrack = try XCTUnwrap(audioTracks.first)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration), of: audioTrack, at: .zero)

        let take = directory.appendingPathComponent("take.mp4")
        let export = try XCTUnwrap(AVAssetExportSession(asset: composition,
                                                        presetName: AVAssetExportPresetHEVCHighestQuality))
        try await export.export(to: take, as: .mp4)
        return take
    }
}
