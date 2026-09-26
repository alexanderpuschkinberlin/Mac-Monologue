import XCTest
@testable import Mac_Monologue

final class AutoCutTests: XCTestCase {
    func testStartsOnTheHead() {
        var cut = AutoCut()
        XCTAssertFalse(cut.showsScreen(touching: false, now: 10))
    }

    func testTouchShowsTheScreenAtOnce() {
        var cut = AutoCut()
        XCTAssertFalse(cut.showsScreen(touching: false, now: 10))
        XCTAssertTrue(cut.showsScreen(touching: true, now: 10.03))
    }

    func testBriefLiftKeepsTheScreen() {
        var cut = AutoCut()
        _ = cut.showsScreen(touching: true, now: 10)
        XCTAssertTrue(cut.showsScreen(touching: false, now: 10 + AutoCut.holdSeconds - 0.05))
    }

    func testLiftLongerThanTheHoldCutsToTheHead() {
        var cut = AutoCut()
        _ = cut.showsScreen(touching: true, now: 10)
        XCTAssertFalse(cut.showsScreen(touching: false, now: 10 + AutoCut.holdSeconds + 0.01))
    }

    func testTouchingAgainRestartsTheHold() {
        var cut = AutoCut()
        _ = cut.showsScreen(touching: true, now: 10)
        _ = cut.showsScreen(touching: true, now: 10.5)
        XCTAssertTrue(cut.showsScreen(touching: false, now: 10.5 + AutoCut.holdSeconds - 0.05))
        XCTAssertFalse(cut.showsScreen(touching: false, now: 10.5 + AutoCut.holdSeconds + 0.01))
    }
}
