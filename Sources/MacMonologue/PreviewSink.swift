import AVFoundation
import CoreMedia
import CoreVideo

/// Hands composited frames to the live preview's video renderer.
///
/// In screen mode the preview is the compositor's own output — the very frames
/// that are recorded — so it cannot show the bubble anywhere the file does not.
///
/// `AVSampleBufferVideoRenderer` is built to be fed from a background queue; this
/// is only ever called from the capture output queue.
final class PreviewSink: @unchecked Sendable {
    private let renderer: AVSampleBufferVideoRenderer

    init(renderer: AVSampleBufferVideoRenderer) {
        self.renderer = renderer
    }

    func show(_ pixelBuffer: CVPixelBuffer) {
        guard let sampleBuffer = ImageSampleBuffer.make(
            imageBuffer: pixelBuffer,
            presentationTime: CMClockGetTime(CMClockGetHostTimeClock()),
            duration: .invalid
        ) else { return }

        // No timebase drives this renderer: every frame is shown on arrival.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        if renderer.status == .failed { renderer.flush() }
        if renderer.isReadyForMoreMediaData { renderer.enqueue(sampleBuffer) }
    }
}
