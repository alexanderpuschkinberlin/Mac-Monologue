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
    private let queue: DispatchQueue
    private let recorder: TakeRecorder

    /// Every microphone buffer, including while idle or paused — the meter has to
    /// be live before you start, which is the whole point of having one.
    /// Called on `queue`; the buffer must not escape it.
    var onMicrophoneBuffer: ((CMSampleBuffer) -> Void)?

    init(queue: DispatchQueue, recorder: TakeRecorder) {
        self.queue = queue
        self.recorder = recorder
        super.init()
    }

    private func handleCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        recorder.append(sampleBuffer, to: .video)
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
