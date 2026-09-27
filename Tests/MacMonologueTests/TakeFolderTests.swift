import XCTest
@testable import Mac_Monologue

final class TakeFolderTests: XCTestCase {
    private var directory: URL!
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var take: String { (TakeRecorder.filename(for: date) as NSString).deletingPathExtension }

    func testEachTakeGetsAFolderNamedLikeTheFile() {
        let video = TakeRecorder.destination(in: directory, date: date)
        XCTAssertEqual(video.lastPathComponent, "\(take).mp4")
        XCTAssertEqual(video.deletingLastPathComponent().lastPathComponent, take)
        XCTAssertEqual(video.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL,
                       directory.standardizedFileURL)
    }

    func testATakeInTheSameSecondGetsASuffix() throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(take),
                                                withIntermediateDirectories: false)
        let video = TakeRecorder.destination(in: directory, date: date)
        XCTAssertEqual(video.lastPathComponent, "\(take)-2.mp4")
        XCTAssertEqual(video.deletingLastPathComponent().lastPathComponent, "\(take)-2")
    }

    func testTheFolderIsOnlyTheTakesOwn() {
        let video = TakeRecorder.destination(in: directory, date: date)
        XCTAssertEqual(TakeRecorder.takeFolder(of: video, in: directory), video.deletingLastPathComponent())

        // A take from before 0.7.1 lies loose: its folder is everyone's.
        let loose = directory.appendingPathComponent("\(take).mp4")
        XCTAssertNil(TakeRecorder.takeFolder(of: loose, in: directory))
    }

    func testSubtitlesLandInTheTakesFolder() {
        let video = TakeRecorder.destination(in: directory, date: date)
        XCTAssertEqual(SRTWriter.url(nextTo: video, language: .german).deletingLastPathComponent(),
                       video.deletingLastPathComponent())
    }
}
