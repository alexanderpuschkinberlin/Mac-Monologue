import XCTest
@testable import Mac_Monologue

final class VideoQualityTests: XCTestCase {
    func testHighStaysUnderOneHundredMegabytesForTenMinutes() {
        XCTAssertLessThanOrEqual(VideoQuality.high.estimatedMegabytes(minutes: 10), 100)
        XCTAssertLessThanOrEqual(VideoQuality.high.nominalMegabytesPerTenMinutes, 100,
                                 "High's bitrates alone must fit, too")
    }

    func testStepsGrowInSize() {
        let sizes = VideoQuality.allCases.map { $0.estimatedMegabytes(minutes: 10) }
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(Set(sizes).count, sizes.count)
    }

    func testEstimatesMatchWhatTheLabelsPromise() {
        XCTAssertEqual(VideoQuality.economical.sizeLabel, "≈ 35 MB per 10 min")
        XCTAssertEqual(VideoQuality.medium.sizeLabel, "≈ 75 MB per 10 min")
        XCTAssertEqual(VideoQuality.high.sizeLabel, "≈ 100 MB per 10 min")
        XCTAssertEqual(VideoQuality.veryHigh.sizeLabel, "≈ 300 MB per 10 min")
    }

    func testMediumIsTheStandard() {
        XCTAssertEqual(VideoQuality.standard, .medium)
    }

    func testCameraIsScaledDownButNeverUp() {
        XCTAssertTrue(VideoQuality.economical.cameraSize(width: 1920, height: 1080) == (1280, 720))
        XCTAssertTrue(VideoQuality.medium.cameraSize(width: 1920, height: 1080) == (1920, 1080))
        XCTAssertTrue(VideoQuality.medium.cameraSize(width: 1280, height: 720) == (1280, 720))
        XCTAssertTrue(VideoQuality.medium.cameraSize(width: 1920, height: 1440) == (1920, 1440))
        XCTAssertTrue(VideoQuality.economical.cameraSize(width: 1920, height: 1440) == (1280, 960))
    }

    func testVeryHighKeepsTheCameraSize() {
        XCTAssertTrue(VideoQuality.veryHigh.cameraSize(width: 3840, height: 2160) == (3840, 2160))
    }

    func testPortraitCameraKeepsItsOrientation() {
        XCTAssertTrue(VideoQuality.economical.cameraSize(width: 1080, height: 1920) == (720, 1280))
    }
}

@MainActor
final class CameraRotationTests: XCTestCase {
    func testSidewaysAnglesSwapWidthAndHeight() {
        XCTAssertFalse(CaptureController.isSideways(0))
        XCTAssertTrue(CaptureController.isSideways(90))
        XCTAssertFalse(CaptureController.isSideways(180))
        XCTAssertTrue(CaptureController.isSideways(270))
        XCTAssertTrue(CaptureController.isSideways(-90))
        XCTAssertTrue(CaptureController.isSideways(89.9999))
    }
}
