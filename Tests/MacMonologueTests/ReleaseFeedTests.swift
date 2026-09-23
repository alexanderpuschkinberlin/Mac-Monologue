import XCTest
@testable import Mac_Monologue

/// Shaped on a real response from the GitHub REST API — including the Windows
/// line endings and `*` bullets GitHub stores release notes with.
final class ReleaseFeedTests: XCTestCase {
    private static func release(_ tag: String, draft: Bool = false, prerelease: Bool = false,
                                asset: String = "Mac-Monologue.zip", digest: String? = "sha256:ABCDEF0123") -> String {
        """
        {
          "tag_name": "\(tag)", "name": "Mac-Monologue \(tag)",
          "body": "* First change\\r\\n* Second change",
          "draft": \(draft), "prerelease": \(prerelease),
          "published_at": "2026-10-02T09:30:00Z",
          "html_url": "https://github.com/alexanderpuschkinberlin/Mac-Monologue/releases/tag/\(tag)",
          "assets": [{
            "name": "\(asset)", "size": 700000, "content_type": "application/zip",
            "browser_download_url": "https://github.com/alexanderpuschkinberlin/Mac-Monologue/releases/download/\(tag)/\(asset)",
            "digest": \(digest.map { "\"\($0)\"" } ?? "null")
          }]
        }
        """
    }

    private func decode(_ releases: [String]) throws -> [Release] {
        try ReleaseFeed.decode(Data("[\(releases.joined(separator: ","))]".utf8))
    }

    func testDecodesTheFieldsTheUpdaterNeeds() throws {
        let release = try XCTUnwrap(decode([Self.release("v0.4.0")]).first)
        XCTAssertEqual(release.version, AppVersion("0.4.0"))
        XCTAssertEqual(release.appAsset?.size, 700000)
        XCTAssertEqual(release.appAsset?.downloadURL.lastPathComponent, "Mac-Monologue.zip")
        XCTAssertEqual(release.appAssetSHA256, "abcdef0123", "lowercased, prefix removed")
        XCTAssertNotNil(release.publishedAt)
    }

    func testANullDigestDecodes() throws {
        let release = try XCTUnwrap(decode([Self.release("v0.4.0", digest: nil)]).first)
        XCTAssertNil(release.appAssetSHA256)
    }

    func testOffersOnlyNewerPublishedReleasesWithTheApp() throws {
        let releases = try decode([
            Self.release("v0.5.0", draft: true),
            Self.release("v0.4.1", prerelease: true),
            Self.release("v0.4.0"),
            Self.release("v0.3.5", asset: "Something-else.zip"),
            Self.release("v0.3.1"),
            Self.release("v0.3.0"),
            Self.release("v0.2.0"),
        ])
        let offered = ReleaseFeed.updates(in: releases, newerThan: AppVersion("0.3.0")!)
        XCTAssertEqual(offered.map(\.tagName), ["v0.4.0", "v0.3.1"],
                       "drafts, pre-releases, releases without the app and older versions are left out")
    }

    func testNewestComesFirstWhateverTheOrderGitHubUses() throws {
        let releases = try decode([Self.release("v0.3.1"), Self.release("v0.10.0"), Self.release("v0.4.0")])
        XCTAssertEqual(ReleaseFeed.updates(in: releases, newerThan: AppVersion("0.3.0")!).map(\.tagName),
                       ["v0.10.0", "v0.4.0", "v0.3.1"])
    }

    func testNothingToOfferWhenUpToDate() throws {
        let releases = try decode([Self.release("v0.3.0"), Self.release("v0.2.0")])
        XCTAssertTrue(ReleaseFeed.updates(in: releases, newerThan: AppVersion("0.3.0")!).isEmpty)
    }

    func testTheDownloadLinkIsPermanent() {
        XCTAssertEqual(ReleaseFeed.latestDownloadURL.absoluteString,
                       "https://github.com/alexanderpuschkinberlin/Mac-Monologue/releases/latest/download/Mac-Monologue.zip")
    }
}
