import AVFoundation
import Foundation

/// The one place sample buffers arrive, and the one place that decides where they
/// go: to the recorder, the level meter, and later the compositor and mixer.
///
/// `CaptureController` is `@MainActor` and cannot be a capture delegate, and
/// `TakeRecorder` should not know where its buffers come from. This is the seam.
///
/// All state is confined to `queue` — the same queue `TakeRecorder` is confined to,
/// so calls into it never hop. `@unchecked Sendable` on that basis.
final class CaptureRouter: NSObject, @unchecked Sendable {
    /// What the router does with incoming frames. Replaced as a whole, on `queue`.
    struct Configuration: Equatable, Sendable {
        var mirrorsRecording = false
    }

    private let queue: DispatchQueue
    private let recorder: TakeRecorder
    private let compositor = FrameCompositor()
    private var configuration = Configuration()

    /// Every microphone buffer, including while idle or paused — the meter has to
    /// be live before you start, which is the whole point of having one.
    /// Called on `queue`; the buffer must not escape it.
    var onMicrophoneBuffer: ((CMSampleBuffer) -> Void)?

    init(queue: DispatchQueue, recorder: TakeRecorder) {
        self.queue = queue
        self.recorder = recorder
        super.init()
    }

    /// Takes effect from the next frame. Safe to call from any thread.
    func configure(_ configuration: Configuration) {
        queue.async { [self] in self.configuration = configuration }
    }

    private func handleCameraFrame(_ sampleBuffer: CMSampleBuffer) {
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
        recorder.append(sampleBuffer, to: .audio)
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
