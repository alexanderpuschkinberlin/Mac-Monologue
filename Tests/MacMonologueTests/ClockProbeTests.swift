import CoreMedia
import XCTest
@testable import Mac_Monologue

final class ClockProbeTests: XCTestCase {
    func testNoCommonAncestorIsUnrelated() {
        XCTAssertEqual(ClockProbe.verdict(relativeRate: 0, offsetSeconds: 0), .unrelated)
        XCTAssertEqual(ClockProbe.verdict(relativeRate: .nan, offsetSeconds: 0), .unrelated)
    }

    func testMatchingClocksAgree() {
        XCTAssertEqual(ClockProbe.verdict(relativeRate: 1.00001, offsetSeconds: 0.0001), .agree)
    }

    func testRateOrOffsetOutOfBoundsIsDrifting() {
        XCTAssertEqual(ClockProbe.verdict(relativeRate: 1.01, offsetSeconds: 0), .drifting)
        XCTAssertEqual(ClockProbe.verdict(relativeRate: 1, offsetSeconds: 0.05), .drifting)
    }

    func testTheHostClockAgreesWithItself() {
        let host = CMClockGetHostTimeClock()
        XCTAssertEqual(ClockProbe.measure(from: host, to: host).verdict, .agree)
    }
}
