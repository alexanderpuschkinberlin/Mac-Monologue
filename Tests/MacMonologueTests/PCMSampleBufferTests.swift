import CoreMedia
import XCTest
@testable import Mac_Monologue

final class PCMSampleBufferTests: XCTestCase {
    func testRoundTripsSamplesAndTiming() throws {
        let input: [Float] = (0..<1_024).map { Float($0) / 1_024 }
        let time = CMTime(value: 48_000, timescale: 48_000)
        let buffer = try XCTUnwrap(PCMSampleBuffer.make(samples: input, presentationTime: time))

        XCTAssertEqual(CMSampleBufferGetNumSamples(buffer), 1_024)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(buffer), time)

        let blockBuffer = try XCTUnwrap(CMSampleBufferGetDataBuffer(buffer))
        var output = [Float](repeating: -1, count: 1_024)
        let status = output.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0,
                                       dataLength: bytes.count, destination: bytes.baseAddress!)
        }
        XCTAssertEqual(status, kCMBlockBufferNoErr)
        XCTAssertEqual(output, input)
    }

    func testEmptyInputMakesNoBuffer() {
        XCTAssertNil(PCMSampleBuffer.make(samples: [], presentationTime: .zero))
    }
}
