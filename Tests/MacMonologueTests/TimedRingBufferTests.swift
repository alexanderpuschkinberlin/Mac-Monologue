import XCTest
@testable import Mac_Monologue

final class TimedRingBufferTests: XCTestCase {
    func testReadsBackWhatWasWritten() {
        var buffer = TimedRingBuffer(capacity: 100)
        buffer.write([1, 2, 3], at: 10)
        XCTAssertEqual(buffer.read(count: 3, from: 10), [1, 2, 3])
    }

    func testUnwrittenPositionsReadAsSilence() {
        var buffer = TimedRingBuffer(capacity: 100)
        buffer.write([1, 2], at: 10)
        XCTAssertEqual(buffer.read(count: 6, from: 8), [0, 0, 1, 2, 0, 0])
    }

    func testAGapIsFilledWithSilenceNotLeftovers() {
        var buffer = TimedRingBuffer(capacity: 8)
        buffer.write(Array(repeating: 9, count: 8), at: 0)   // fill every slot
        buffer.write([1], at: 8)
        buffer.write([2], at: 11)                              // gap at 9 and 10
        XCTAssertEqual(buffer.read(count: 4, from: 8), [1, 0, 0, 2])
    }

    func testKeepsOnlyTheNewestCapacity() {
        var buffer = TimedRingBuffer(capacity: 4)
        buffer.write([1, 2, 3, 4, 5, 6], at: 0)
        XCTAssertEqual(buffer.lowerBound, 2)
        XCTAssertEqual(buffer.read(count: 6, from: 0), [0, 0, 3, 4, 5, 6])
    }

    func testAWriteThatIsTooLateIsDropped() {
        var buffer = TimedRingBuffer(capacity: 4)
        buffer.write([1, 2, 3, 4], at: 10)
        buffer.write([7, 7, 7, 7, 7, 7], at: 12)   // lowerBound moves to 14
        buffer.write([9], at: 5)                   // long gone
        XCTAssertEqual(buffer.read(count: 4, from: 14), [7, 7, 7, 7])
    }

    func testAGapWiderThanTheBufferStartsOver() {
        var buffer = TimedRingBuffer(capacity: 4)
        buffer.write([1, 2], at: 0)
        buffer.write([5], at: 1_000)
        XCTAssertEqual(buffer.lowerBound, 1_000)
        XCTAssertEqual(buffer.read(count: 1, from: 1_000), [5])
        XCTAssertEqual(buffer.read(count: 1, from: 0), [0])
    }

    func testNegativePositionsWork() {
        var buffer = TimedRingBuffer(capacity: 4)
        buffer.write([1, 2, 3], at: -2)
        XCTAssertEqual(buffer.read(count: 3, from: -2), [1, 2, 3])
    }
}
