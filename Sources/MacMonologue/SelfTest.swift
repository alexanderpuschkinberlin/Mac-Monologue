import AVFoundation
import Foundation

/// An opt-in smoke test against real hardware, mirroring omacom/monologue's
/// `bin/test-camera`: the unit tests deliberately never touch a device, so this
/// is the only thing that proves the capture path end to end.
///
/// Records two seconds, pauses for three, records two more, finishes — then
/// prints the result and exits. A correct take is ~4s long, not ~7s.
@MainActor
enum SelfTest {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("--self-test")
    }

    static let recordSeconds: Double = 2
    static let pauseSeconds: Double = 3

    static func run(capture: CaptureController) {
        Task {
            func log(_ message: String) {
                print("[self-test] \(message)")
                fflush(stdout)
            }

            @MainActor
            func waitUntil(timeout: Double = 10, _ condition: @MainActor () -> Bool) async -> Bool {
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    if condition() { return true }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                return false
            }

            guard await waitUntil({ capture.state == .ready }) else {
                log("FAIL: never reached ready (state=\(capture.state.label))")
                exit(1)
            }
            log("ready · \(capture.formatSummary) · audio=\(capture.hasAudio)")

            capture.toggleRecording()
            guard await waitUntil({ capture.state == .recording }) else {
                log("FAIL: did not start recording")
                exit(1)
            }
            try? await Task.sleep(for: .seconds(recordSeconds))

            capture.toggleRecording()
            guard await waitUntil({ capture.state == .paused }) else {
                log("FAIL: did not pause")
                exit(1)
            }
            log("paused at \(String(format: "%.2f", capture.elapsed))s")
            try? await Task.sleep(for: .seconds(pauseSeconds))

            capture.toggleRecording()
            guard await waitUntil({ capture.state == .recording }) else {
                log("FAIL: did not resume")
                exit(1)
            }
            try? await Task.sleep(for: .seconds(recordSeconds))

            capture.finishTake()
            guard await waitUntil(timeout: 20, { capture.state == .preview || capture.banner != nil }) else {
                log("FAIL: finish never completed (state=\(capture.state.label))")
                exit(1)
            }

            if let banner = capture.banner {
                log("FAIL: \(banner)")
                exit(1)
            }
            guard let url = capture.lastRecordingURL else {
                log("FAIL: finished with no file")
                exit(1)
            }

            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? Int) ?? 0

            // Inspect the file itself rather than trusting the UI's numbers: a
            // missing audio track is invisible from in here otherwise.
            let asset = AVURLAsset(url: url)
            let duration = ((try? await asset.load(.duration))?.seconds) ?? 0
            let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

            log("file · \(String(format: "%.2f", duration))s · video=\(videoTracks.count) audio=\(audioTracks.count) · \(size) bytes")

            var failures: [String] = []
            if videoTracks.isEmpty { failures.append("no video track") }
            if capture.hasAudio && audioTracks.isEmpty { failures.append("no audio track") }

            // 2s + 2s recorded around a 3s pause: the pause must not be in the file.
            let expected = recordSeconds * 2
            if abs(duration - expected) > 1.0 {
                failures.append(String(format: "duration %.2fs, expected ~%.0fs", duration, expected))
            }

            guard failures.isEmpty else {
                log("FAIL: \(failures.joined(separator: "; "))")
                exit(1)
            }
            // A test that leaves takes in the user's Movies folder is a bad test.
            try? FileManager.default.removeItem(at: url)
            log("OK · verified and removed \(url.lastPathComponent)")
            exit(0)
        }
    }
}
