import XCTest
@testable import Mac_Monologue

@MainActor
final class MoveToApplicationsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoveToApplicationsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testOffersOnlyOutsideApplications() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(MoveToApplications.shouldOffer(bundleURL: URL(fileURLWithPath: "/Applications/Mac-Monologue.app")))
        XCTAssertFalse(MoveToApplications.shouldOffer(
            bundleURL: URL(fileURLWithPath: home + "/Applications/Mac-Monologue.app")))
        XCTAssertFalse(MoveToApplications.shouldOffer(
            bundleURL: URL(fileURLWithPath: "/Users/x/Mac-Monologue/build/Build/Products/Debug/Mac-Monologue.app")),
                       "never a development build")
    }

    func testOffersFromDownloadsAndTranslocation() {
        guard DevicePreferences.declinedMoveVersion != AppVersion.current?.description else {
            return  // declined on this Mac for this version; the rule is then covered above
        }
        XCTAssertTrue(MoveToApplications.shouldOffer(bundleURL: URL(fileURLWithPath: "/Users/x/Downloads/Mac-Monologue.app")))
        XCTAssertTrue(MoveToApplications.shouldOffer(
            bundleURL: URL(fileURLWithPath: "/private/var/folders/ab/AppTranslocation/1234/d/Mac-Monologue.app")))
    }

    func testMovesAQuarantinedAppAndReplacesAnOlderOne() throws {
        let downloads = directory.appendingPathComponent("Downloads")
        let applications = directory.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let app = downloads.appendingPathComponent("Mac-Monologue.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: app.appendingPathComponent("Contents/version"))
        XCTAssertEqual(setxattr(app.path, "com.apple.quarantine", "0081;00000000;Safari;", 21, 0, 0), 0)

        let installed = applications.appendingPathComponent("Mac-Monologue.app")
        try FileManager.default.createDirectory(at: installed.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: installed.appendingPathComponent("Contents/version"))

        try MoveToApplications.move(from: app, to: installed, trashingOriginal: false)

        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("Contents/version"), encoding: .utf8), "new")
        XCTAssertEqual(getxattr(installed.path, "com.apple.quarantine", nil, 0, 0, 0), -1, "no longer quarantined")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: applications.path)
        XCTAssertEqual(leftovers, ["Mac-Monologue.app"], "no staging copy left behind")
    }

    func testAnUntranslocatedAppIsItsOwnOriginal() {
        let url = URL(fileURLWithPath: "/Users/x/Downloads/Mac-Monologue.app")
        XCTAssertEqual(MoveToApplications.originalLocation(of: url), url)
    }
}
