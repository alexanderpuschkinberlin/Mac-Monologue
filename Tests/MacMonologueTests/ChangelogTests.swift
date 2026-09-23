import XCTest
@testable import Mac_Monologue

final class ChangelogTests: XCTestCase {
    func testBulletsInBothStylesAndWindowsLineEndings() {
        XCTAssertEqual(ChangelogFormatter.items(in: "* One\r\n- Two\r\n"),
                       [.bullet("One"), .bullet("Two")])
    }

    func testParagraphsAreJoinedAndHeadingsDropped() {
        let body = "## 0.3.0\n\nA first line\nthat continues.\n\n- A bullet"
        XCTAssertEqual(ChangelogFormatter.items(in: body),
                       [.paragraph("A first line that continues."), .bullet("A bullet")])
    }

    func testAWrappedBulletStaysOneBullet() {
        let body = "- Mac-Monologue now tells you when a new version is out,\n  and installs it for you."
        XCTAssertEqual(ChangelogFormatter.items(in: body),
                       [.bullet("Mac-Monologue now tells you when a new version is out, and installs it for you.")])
    }

    /// The file `bin/publish` reads release notes from: every heading must be a
    /// version, and newest first, or the wrong section would be published.
    func testTheChangelogFileIsWellFormed() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)

        let versions = text.split(separator: "\n")
            .filter { $0.hasPrefix("## ") }
            .map { $0.dropFirst(3).split(separator: " ").first.map(String.init) ?? "" }

        XCTAssertFalse(versions.isEmpty)
        let parsed = versions.compactMap(AppVersion.init)
        XCTAssertEqual(parsed.count, versions.count, "every heading must start with a version: \(versions)")
        XCTAssertEqual(parsed, parsed.sorted(by: >), "newest first")
        XCTAssertEqual(Set(parsed).count, parsed.count, "no version twice")
    }
}
