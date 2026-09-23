import AVFoundation
import CoreImage
import Foundation
import ScreenCaptureKit

/// The one place sample buffers arrive, and the one place that decides where they
/// go: to the recorder, the level meter, the compositor and the live preview.
///
/// `CaptureController` is `@MainActor` and cannot be a capture delegate, and
/// `TakeRecorder` should not know where its buffers come from. This is the seam.
///
/// Camera, microphone *and* screen all deliver on `queue` — the queue
/// `TakeRecorder` is confined to — so nothing here needs a lock and calls into the
/// recorder never hop. `@unchecked Sendable` on that basis.
final class CaptureRouter: NSObject, @unchecked Sendable {
    /// What the router does with incoming frames. Replaced as a whole.
    struct Configuration: Equatable, Sendable {
        var mode: CaptureMode = .camera
        var mirrorsRecording = false
        var bubble = BubbleLayout()
        var canvasWidth = 0
        var canvasHeight = 0

        var isScreenMode: Bool { mode == .screenAndCamera && canvasWidth > 0 && canvasHeight > 0 }
    }

    /// If no camera frame has arrived for this long in screen mode, the screen is
    /// recorded on its own rather than freezing — Continuity Camera drops out every
    /// time the iPhone locks, and a presentation must not stop because of it.
    static let cameraStallSeconds: CFTimeInterval = 0.25
    private static let frameDuration = CMTime(value: 1, timescale: 30)

    private let queue: DispatchQueue
    private let recorder: TakeRecorder
    private let compositor = FrameCompositor()
    private var configuration = Configuration()
    private var latestScreen: CVPixelBuffer?
    private var lastCameraFrame: CFTimeInterval = 0
    private var previewSink: PreviewSink?
    private var fallbackTimer: DispatchSourceTimer?

    /// Present only during a screen-mode take: the microphone and system audio are
    /// summed into one track rather than written as two.
    private var mixer: AudioMixer?
    /// ScreenCaptureKit's clock. System audio is converted from it into the
    /// capture session's — the one conversion between clocks anywhere in the app.
    private var screenClock: CMClock?
    private var hasProbedClocks = false

    /// Once per take, whether the two clocks could be related at all.
    var onClockReading: (@Sendable (ClockProbe.Reading) -> Void)?

    /// Every microphone buffer, including while idle or paused — the meter has to
    /// be live before you start, which is the whole point of having one.
    /// Called on `queue`; the buffer must not escape it.
    var onMicrophoneBuffer: ((CMSampleBuffer) -> Void)?

    init(queue: DispatchQueue, recorder: TakeRecorder) {
        self.queue = queue
        self.recorder = recorder
        super.init()
        startFallbackTimer()
        recorder.onWillFinish = { [weak self] in self?.flushMixer() }
    }

    /// Takes effect from the next frame. Safe to call from any thread.
    func configure(_ configuration: Configuration) {
        queue.async { [self] in
            self.configuration = configuration
            if !configuration.isScreenMode { latestScreen = nil }
        }
    }

    func setPreviewSink(_ sink: PreviewSink?) {
        queue.async { [self] in previewSink = sink }
    }

    func setScreenClock(_ clock: CMClock?) {
        nonisolated(unsafe) let clock = clock
        queue.async { [self] in screenClock = clock }
    }

    /// Call before starting a take, so its audio starts from an empty mixer.
    func prepareTake(microphonePresent: Bool) {
        queue.async { [self] in
            mixer = configuration.isScreenMode ? AudioMixer(microphoneIsMaster: microphonePresent) : nil
            hasProbedClocks = false
        }
    }

    // MARK: - Camera

    private func handleCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        lastCameraFrame = CACurrentMediaTime()

        if configuration.isScreenMode {
            // The camera sets the pace in screen mode: ScreenCaptureKit only sends
            // a frame when the screen changes, and a still slide would otherwise
            // freeze the face talking over it.
            guard let camera = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            composeScreen(camera: camera,
                          presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                          duration: CMSampleBufferGetDuration(sampleBuffer))
            return
        }

        guard configuration.mirrorsRecording else {
            // The unmirrored camera is passed through untouched — the path every
            // take used before the compositor existed, byte for byte.
            recorder.append(sampleBuffer, to: .video)
            return
        }
        // Rendering is skipped entirely unless a take is being written; the
        // live preview does its own mirroring.
        guard recorder.isWriting,
              let camera = CMSampleBufferGetImageBuffer(sampleBuffer),
              let rendered = compositor.renderCamera(camera, mirrored: true),
              let composited = ImageSampleBuffer.make(imageBuffer: rendered, timingFrom: sampleBuffer)
        else { return }
        recorder.append(composited, to: .video)
    }

    private func handleMicrophone(_ sampleBuffer: CMSampleBuffer) {
        onMicrophoneBuffer?(sampleBuffer)

        guard let mixer else {
            recorder.append(sampleBuffer, to: .audio)
            return
        }
        // nil while paused or before the first frame: the same gate every buffer
        // passes, so a pause removes dead air from both sources alike.
        guard let takeTime = recorder.takeTime(
            for: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) else { return }
        mixer.pushMicrophone(sampleBuffer, takeTime: takeTime)
        writeMixedAudio()
    }

    // MARK: - System audio

    private func handleSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let mixer else { return }
        let captureClock = recorder.currentSourceClock()
        var timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if let screenClock {
            timestamp = CMSyncConvertTime(timestamp, from: screenClock, to: captureClock)
            if !hasProbedClocks {
                hasProbedClocks = true
                onClockReading?(ClockProbe.measure(from: screenClock, to: captureClock))
            }
        }

        guard let takeTime = recorder.takeTime(for: timestamp) else { return }
        mixer.pushSystem(sampleBuffer, takeTime: takeTime)
        writeMixedAudio()
    }

    private func writeMixedAudio() {
        guard let mixer else { return }
        for block in mixer.drainReady() {
            recorder.appendInTakeTime(block, to: .audio)
        }
    }

    /// Hands over the hold-back at the end of a take. Runs inside `finish`.
    private func flushMixer() {
        guard let mixer else { return }
        for block in mixer.flush() {
            recorder.appendInTakeTime(block, to: .audio)
        }
        self.mixer = nil
    }

    // MARK: - Screen

    private func handleScreenFrame(_ sampleBuffer: CMSampleBuffer) {
        // Only a complete frame carries a new image; idle frames mean "unchanged",
        // and the last image stays valid.
        guard let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                            as? [[SCStreamFrameInfo: Any]])?.first,
              let rawStatus = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus),
              status == .complete || status == .started,
              let image = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        latestScreen = image
    }

    private func startFallbackTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in self?.fallbackTick() }
        timer.resume()
        fallbackTimer = timer
    }

    /// Keeps screen mode moving while no camera frames arrive.
    private func fallbackTick() {
        guard configuration.isScreenMode, latestScreen != nil,
              CACurrentMediaTime() - lastCameraFrame > Self.cameraStallSeconds else { return }
        composeScreen(camera: nil, presentationTime: recorder.currentCaptureTime(),
                      duration: Self.frameDuration)
    }

    private func composeScreen(camera: CVPixelBuffer?, presentationTime: CMTime, duration: CMTime) {
        let writing = recorder.isWriting
        guard writing || previewSink != nil else { return }

        let bubble = camera == nil ? .zero : configuration.bubble.frame(
            canvasWidth: configuration.canvasWidth, canvasHeight: configuration.canvasHeight)
        guard let rendered = compositor.renderScreen(
            screen: latestScreen, camera: camera,
            canvasWidth: configuration.canvasWidth, canvasHeight: configuration.canvasHeight,
            bubble: bubble, mirrorsCamera: configuration.mirrorsRecording
        ) else { return }

        previewSink?.show(rendered)

        if writing, let frame = ImageSampleBuffer.make(imageBuffer: rendered,
                                                        presentationTime: presentationTime,
                                                        duration: duration) {
            recorder.append(frame, to: .video)
        }
    }
}

extension CaptureRouter: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Already on `queue` — both capture outputs deliver here.
        if output is AVCaptureVideoDataOutput {
            handleCameraFrame(sampleBuffer)
        } else {
            handleMicrophone(sampleBuffer)
        }
    }
}

extension CaptureRouter: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        // Already on `queue` — ScreenCaptureKit was handed it as its sample queue.
        switch type {
        case .screen: handleScreenFrame(sampleBuffer)
        case .audio: handleSystemAudio(sampleBuffer)
        default: break
        }
    }
}
