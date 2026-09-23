import CoreMedia
import CoreVideo

/// Wraps a rendered pixel buffer back into a sample buffer the recorder can append.
enum ImageSampleBuffer {
    /// Carries over the source frame's timing exactly: a composited frame is the
    /// camera frame it was built from, as far as the timeline is concerned.
    static func make(imageBuffer: CVPixelBuffer, timingFrom source: CMSampleBuffer) -> CMSampleBuffer? {
        make(
            imageBuffer: imageBuffer,
            presentationTime: CMSampleBufferGetPresentationTimeStamp(source),
            duration: CMSampleBufferGetDuration(source)
        )
    }

    static func make(imageBuffer: CVPixelBuffer, presentationTime: CMTime, duration: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        return sampleBuffer
    }
}
