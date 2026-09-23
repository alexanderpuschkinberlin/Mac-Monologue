import XCTest
@testable import Mac_Monologue

final class AppVersionTests: XCTestCase {
    private func v(_ string: String) -> AppVersion { AppVersion(string)! }

    func testReadsPlainAndTaggedVersions() {
        XCTAssertEqual(v("0.3.0").components, [0, 3, 0])
        XCTAssertEqual(v("v0.3.0"), v("0.3.0"))
        XCTAssertEqual(v("V1.2"), v("1.2.0"))
    }

    func testRejectsWhatIsNotAVersion() {
        for text in ["", "v", "1..2", "1.2.x", "abc", "1.2.3.4.5", "-1.0", "1.0-beta", "١.٢"] {
            XCTAssertNil(AppVersion(text), text)
        }
    }

    func testOrdering() {
        XCTAssertLessThan(v("0.2.0"), v("0.3.0"))
        XCTAssertLessThan(v("0.9.0"), v("0.10.0"), "numeric, not alphabetical")
        XCTAssertLessThan(v("0.3"), v("0.3.1"))
        XCTAssertLessThan(v("1.9.9"), v("2"))
        XCTAssertFalse(v("0.3.0") < v("0.3"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(v("0.3"), v("0.3.0"))
        XCTAssertEqual(Set([v("0.3"), v("0.3.0")]).count, 1)
    }

    func testDescription() {
        XCTAssertEqual(v("v0.3.0").description, "0.3.0")
    }
}
