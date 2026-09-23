import Foundation
import Security
import XCTest
@testable import Mac_Monologue

/// The check that decides whether a download may replace the app, exercised on
/// small apps built and signed here — signed with the real certificate, ad hoc,
/// and not at all.
final class UpdateVerifierTests: XCTestCase {
    private var directory: URL!
    private static let identifier = "io.github.alexanderpuschkinberlin.mac-monologue"
    private static let certificate = "Mac-Monologue Self-Signed"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    /// A minimal app bundle around a freshly compiled program. `payload` goes into
    /// the binary, so two bundles are genuinely different code.
    private func makeApp(_ name: String, identifier: String = identifier, version: String = "0.3.1",
                         payload: String = "a") throws -> URL {
        let app = directory.appendingPathComponent("\(name).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("\(name).c")
        try "const char *payload = \"\(payload)\"; int main(void) { return payload[0] == 0; }"
            .write(to: source, atomically: true, encoding: .utf8)
        XCTAssertEqual(try run("/usr/bin/xcrun", ["clang", "-o", macOS.appendingPathComponent(name).path, source.path]),
                       0, "compiling the test app")

        let info: [String: Any] = [
            "CFBundleIdentifier": identifier, "CFBundleExecutable": name,
            "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL",
        ]
        (info as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        return app
    }

    @discardableResult
    private func sign(_ app: URL, with identity: String) throws -> Int32 {
        try run("/usr/bin/codesign", ["--force", "--sign", identity, "--timestamp=none", app.path])
    }

    private func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func certificateAvailable() -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-identity", "-p", "codesigning"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output.contains(Self.certificate)
    }

    // MARK: - Checksum

    func testChecksumOfAKnownValue() throws {
        let file = directory.appendingPathComponent("abc")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try UpdateVerifier.sha256(of: file),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testAMatchingChecksumPassesInAnyCase() throws {
        let file = directory.appendingPathComponent("abc")
        try Data("abc".utf8).write(to: file)
        XCTAssertNoThrow(try UpdateVerifier.verifyChecksum(
            of: file, expected: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"))
    }

    func testAWrongChecksumIsRejected() throws {
        let file = directory.appendingPathComponent("abc")
        try Data("abc".utf8).write(to: file)
        XCTAssertThrowsError(try UpdateVerifier.verifyChecksum(of: file, expected: String(repeating: "0", count: 64))) {
            XCTAssertEqual($0 as? UpdateVerifier.Failure, .checksumMismatch)
        }
    }

    func testNoChecksumIsRejectedRatherThanSkipped() throws {
        let file = directory.appendingPathComponent("abc")
        try Data("abc".utf8).write(to: file)
        XCTAssertThrowsError(try UpdateVerifier.verifyChecksum(of: file, expected: nil)) {
            XCTAssertEqual($0 as? UpdateVerifier.Failure, .missingChecksum)
        }
    }

    // MARK: - Signature

    /// The case every real update is: same certificate, different build.
    func testAnotherBuildSignedWithTheSameCertificatePasses() throws {
        try XCTSkipUnless(certificateAvailable(), "the signing certificate is not in this keychain")
        let installed = try makeApp("Installed", payload: "one")
        let update = try makeApp("Update", payload: "two")
        XCTAssertEqual(try sign(installed, with: Self.certificate), 0)
        XCTAssertEqual(try sign(update, with: Self.certificate), 0)

        let requirement = try UpdateVerifier.designatedRequirement(ofAppAt: installed)
        XCTAssertNoThrow(try UpdateVerifier.verifySignature(ofAppAt: update, matching: requirement))
    }

    /// Anyone can sign ad hoc; that must never be enough.
    func testAnAdHocSignedUpdateIsRejected() throws {
        try XCTSkipUnless(certificateAvailable(), "the signing certificate is not in this keychain")
        let installed = try makeApp("Installed", payload: "one")
        let update = try makeApp("Update", payload: "two")
        XCTAssertEqual(try sign(installed, with: Self.certificate), 0)
        XCTAssertEqual(try sign(update, with: "-"), 0)

        let requirement = try UpdateVerifier.designatedRequirement(ofAppAt: installed)
        XCTAssertThrowsError(try UpdateVerifier.verifySignature(ofAppAt: update, matching: requirement)) {
            XCTAssertEqual($0 as? UpdateVerifier.Failure, .signedBySomeoneElse)
        }
    }

    /// Without the certificate available, the same principle holds for ad hoc
    /// signatures: a different build does not match.
    func testADifferentAdHocBuildDoesNotMatch() throws {
        let installed = try makeApp("Installed", payload: "one")
        let update = try makeApp("Update", payload: "two")
        XCTAssertEqual(try sign(installed, with: "-"), 0)
        XCTAssertEqual(try sign(update, with: "-"), 0)

        let requirement = try UpdateVerifier.designatedRequirement(ofAppAt: installed)
        XCTAssertThrowsError(try UpdateVerifier.verifySignature(ofAppAt: update, matching: requirement)) {
            XCTAssertEqual($0 as? UpdateVerifier.Failure, .signedBySomeoneElse)
        }
    }

    /// Signed properly, then changed: the signature no longer covers what is
    /// there. (A truly unsigned app cannot be made on Apple silicon — the linker
    /// signs every arm64 binary — so tampering is the case that matters.)
    func testAnUpdateChangedAfterSigningIsRejected() throws {
        let installed = try makeApp("Installed", payload: "one")
        let update = try makeApp("Update", payload: "two")
        let identity = certificateAvailable() ? Self.certificate : "-"
        XCTAssertEqual(try sign(installed, with: identity), 0)
        XCTAssertEqual(try sign(update, with: identity), 0)

        let plist = update.appendingPathComponent("Contents/Info.plist")
        let info = NSMutableDictionary(contentsOf: plist)!
        info["CFBundleShortVersionString"] = "9.9.9"
        info.write(to: plist, atomically: true)

        let requirement = try UpdateVerifier.designatedRequirement(ofAppAt: installed)
        XCTAssertThrowsError(try UpdateVerifier.verifySignature(ofAppAt: update, matching: requirement)) {
            XCTAssertEqual($0 as? UpdateVerifier.Failure, .notSigned)
        }
    }

    func testTheRunningAppHasARequirement() {
        XCTAssertNoThrow(try UpdateVerifier.ownDesignatedRequirement())
    }

    // MARK: - Identity

    func testTheRightAppAndVersionPass() throws {
        let app = try makeApp("Update", version: "0.3.1")
        XCTAssertNoThrow(try UpdateVerifier.verifyBundle(at: app, identifier: Self.identifier,
                                                         version: AppVersion("0.3.1")!))
    }

    func testADifferentAppIsRejected() throws {
        let app = try makeApp("Update", identifier: "com.example.other")
        XCTAssertThrowsError(try UpdateVerifier.verifyBundle(at: app, identifier: Self.identifier,
                                                             version: AppVersion("0.3.1")!)) {
            XCTAssertEqual($0 as? UpdateVerifier.Failure, .wrongApp)
        }
    }

    func testAVersionOtherThanTheReleaseClaimsIsRejected() throws {
        let app = try makeApp("Update", version: "0.2.0")
        XCTAssertThrowsError(try UpdateVerifier.verifyBundle(at: app, identifier: Self.identifier,
                                                             version: AppVersion("0.3.1")!)) {
            XCTAssertEqual($0 as? UpdateVerifier.Failure, .wrongVersion(expected: "0.3.1", found: "0.2.0"))
        }
    }
}
