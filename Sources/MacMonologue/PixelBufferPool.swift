import CoreVideo
import Foundation

/// A fixed-size pool of BGRA pixel buffers for the compositor to render into.
///
/// Owned here rather than borrowed from `AVAssetWriterInputPixelBufferAdaptor`:
/// that pool only exists once writing has started, and the compositor has to run
/// before then — for the live preview.
///
/// BGRA rather than 4:2:0 because Core Image renders into it unambiguously; the
/// HEVC encoder converts on the way in.
final class PixelBufferPool {
    let width: Int
    let height: Int
    private let pool: CVPixelBufferPool

    /// Buffers still held downstream beyond this count mean the writer has stalled.
    /// Allocation then fails fast and the frame is dropped, instead of the pool
    /// growing without bound behind it.
    private let allocationThreshold = 16

    private(set) var exhaustedCount = 0

    init?(width: Int, height: Int) {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else { return nil }
        self.width = width
        self.height = height
        self.pool = pool
    }

    func makeBuffer() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let auxiliary = [kCVPixelBufferPoolAllocationThresholdKey as String: allocationThreshold]
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            nil, pool, auxiliary as CFDictionary, &buffer
        )
        if status == kCVReturnWouldExceedAllocationThreshold {
            exhaustedCount += 1
            return nil
        }
        guard status == kCVReturnSuccess, let buffer else { return nil }

        // Tag the colour space, so the encoder does not have to guess it.
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey,
                              kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey,
                              kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        return buffer
    }
}
