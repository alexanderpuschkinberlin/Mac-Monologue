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

    static let pauseSeconds: Double = 3

    /// `--seconds=N` records N seconds on each side of the pause instead of 2 —
    /// long enough for the file size to say something about the bitrate.
    static var recordSeconds: Double {
        value(of: "--seconds").flatMap(Double.init) ?? 2
    }

    /// `--quality=high` and so on; otherwise the user's own choice.
    static var quality: VideoQuality? {
        value(of: "--quality").flatMap(VideoQuality.init)
    }

    private static func value(of flag: String) -> String? {
        CommandLine.arguments.first { $0.hasPrefix(flag + "=") }.map { String($0.dropFirst(flag.count + 1)) }
    }

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

            let screenOnly = CommandLine.arguments.contains("--screen-only")
            let screenMode = screenOnly || CommandLine.arguments.contains("--screen")
            if screenMode, !ScreenAccess.isGranted {
                log("SKIP: no screen recording permission for this process — the screen phase "
                    + "needs it (System Settings › Privacy & Security › Screen & System Audio Recording).")
                exit(0)
            }
            capture.mode = screenOnly ? .screen : screenMode ? .screenAndCamera : .camera
            capture.mirrorsRecording = CommandLine.arguments.contains("--mirror")
            if let quality { capture.videoQuality = quality }
            if CommandLine.arguments.contains("--no-mic") {
                capture.selectedMicrophoneID = DeviceOption.noAudioID
            }

            if screenMode {
                // The user's remembered screen may be a monitor that is unplugged
                // right now — the app rightly refuses to record another one. The
                // test is not about that choice, so it takes a connected screen,
                // without saving it over the user's own.
                _ = await waitUntil({ !capture.displays.isEmpty })
                let chosen = capture.displays.first { $0.id == capture.selectedDisplayID }
                if chosen?.isAvailable != true,
                   let connected = capture.displays.first(where: { $0.id == CGMainDisplayID() && $0.isAvailable })
                    ?? capture.displays.first(where: \.isAvailable) {
                    capture.selectedDisplayID = connected.id
                }
            }

            guard await waitUntil(timeout: 15, { capture.state == .ready && capture.canRecord }) else {
                log("FAIL: never became ready to record (state=\(capture.state.label), "
                    + "screenAccess=\(capture.screenAccess), banner=\(capture.banner ?? "-"))")
                exit(1)
            }
            // Let a couple of seconds of frames flow, so the take opens on real
            // screen content rather than the black before the first frame.
            if screenMode { try? await Task.sleep(for: .seconds(1)) }
            log("global shortcuts · \(capture.toggleShortcut.displayString) \(capture.finishShortcut.displayString) · "
                + (capture.unavailableShortcuts.isEmpty ? "registered" : "FAILED: \(capture.unavailableShortcuts)"))
            if !capture.unavailableShortcuts.isEmpty {
                log("FAIL: global shortcuts could not be registered")
                exit(1)
            }
            log("ready · \(capture.formatSummary) · microphone=\(capture.hasAudio) · "
                + "audio track=\(capture.recordsAudio) · mirrored=\(capture.mirrorsRecording)")

            let viaHotkeys = CommandLine.arguments.contains("--hotkeys")
            if viaHotkeys, !CGPreflightPostEventAccess() {
                // macOS silently drops synthetic key presses from a process without
                // the Accessibility permission — that would read as the shortcuts
                // failing when it is the test that cannot type.
                log("SKIP: this process may not send key presses (System Settings › Privacy & "
                    + "Security › Accessibility). The shortcuts are registered; test them by hand.")
                exit(0)
            }
            // With --hotkeys the take is driven by synthetic presses of the global
            // shortcuts, delivered to the system as if typed in another app.
            @MainActor func toggle() {
                viaHotkeys ? HotkeyProbe.press(capture.toggleShortcut) : capture.toggleRecording()
            }
            @MainActor func finish() {
                viaHotkeys ? HotkeyProbe.press(capture.finishShortcut) : capture.finishTake()
            }

            toggle()
            guard await waitUntil({ capture.state == .recording }) else {
                log("FAIL: did not start recording" + (viaHotkeys ? " from the global shortcut" : ""))
                exit(1)
            }
            try? await Task.sleep(for: .seconds(recordSeconds))

            toggle()
            guard await waitUntil({ capture.state == .paused }) else {
                log("FAIL: did not pause")
                exit(1)
            }
            log("paused at \(String(format: "%.2f", capture.elapsed))s")
            try? await Task.sleep(for: .seconds(pauseSeconds))

            toggle()
            guard await waitUntil({ capture.state == .recording }) else {
                log("FAIL: did not resume")
                exit(1)
            }
            try? await Task.sleep(for: .seconds(recordSeconds))

            finish()
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

            let naturalSize = (try? await videoTracks.first?.load(.naturalSize)) ?? .zero
            log("file · \(String(format: "%.2f", duration))s · \(Int(naturalSize.width))×\(Int(naturalSize.height)) · "
                + "video=\(videoTracks.count) audio=\(audioTracks.count) · \(size) bytes")

            var failures: [String] = []
            if videoTracks.isEmpty { failures.append("no video track") }
            // Size per ten minutes, from the recorded length. Keyframes and the
            // file header weigh more in a short take, so only an order of
            // magnitude is checked; --seconds=20 gives a meaningful number.
            let quality = capture.videoQuality
            let perTenMinutes = duration > 0 ? Double(size) / duration * 600 / 1_000_000 : 0
            log(String(format: "quality %@ · %.0f MB per 10 min (promised %@)",
                       quality.title, perTenMinutes, quality.sizeLabel))
            if perTenMinutes > quality.estimatedMegabytes(minutes: 10) * 2 {
                failures.append(String(format: "%.0f MB per 10 min, more than twice the promise", perTenMinutes))
            }
            if !screenMode {
                let expected = quality.cameraSize(width: Int(naturalSize.width), height: Int(naturalSize.height))
                if Int(naturalSize.width) != expected.width || Int(naturalSize.height) != expected.height {
                    failures.append("frame is \(naturalSize), larger than the quality allows")
                }
            }
            if screenMode, naturalSize != capture.canvasSize {
                failures.append("frame is \(naturalSize), expected the canvas \(capture.canvasSize)")
            }
            if capture.recordsAudio && audioTracks.count != 1 {
                failures.append("\(audioTracks.count) audio tracks, expected exactly one")
            }
            if let audio = audioTracks.first,
               let audioDuration = try? await audio.load(.timeRange).duration.seconds {
                log(String(format: "audio track %.2fs", audioDuration))
                if screenMode, abs(audioDuration - duration) > 0.3 {
                    failures.append(String(format: "audio %.2fs vs video %.2fs", audioDuration, duration))
                }
            }
            if let reading = capture.clockReading {
                log(String(format: "clocks · rate %.6f · offset %.4fs · %@", reading.relativeRate,
                           reading.offsetSeconds, String(describing: reading.verdict)))
            }

            // 2s + 2s recorded around a 3s pause: the pause must not be in the file.
            let expected = recordSeconds * 2
            if abs(duration - expected) > 1.0 {
                failures.append(String(format: "duration %.2fs, expected ~%.0fs", duration, expected))
            }

            guard failures.isEmpty else {
                log("FAIL: \(failures.joined(separator: "; "))")
                exit(1)
            }
            // A test that leaves takes in the user's Movies folder is a bad test —
            // unless asked to, so a person can look at what was recorded.
            if CommandLine.arguments.contains("--keep") {
                log("OK · verified and kept \(url.path)")
            } else {
                try? FileManager.default.removeItem(at: url)
                log("OK · verified and removed \(url.lastPathComponent)")
            }
            exit(0)
        }
    }
}

/// Posts a key press to the system, the way a keyboard would.
enum HotkeyProbe {
    static func press(_ shortcut: Shortcut) {
        var flags: CGEventFlags = []
        if shortcut.hasControl { flags.insert(.maskControl) }
        if shortcut.hasOption { flags.insert(.maskAlternate) }
        if shortcut.hasShift { flags.insert(.maskShift) }
        if shortcut.hasCommand { flags.insert(.maskCommand) }
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
