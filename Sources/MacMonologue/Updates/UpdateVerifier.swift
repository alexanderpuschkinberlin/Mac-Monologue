import CryptoKit
import Foundation
import Security

/// Decides whether a downloaded update may replace the running app.
///
/// Two independent checks. The checksum proves the download is the file GitHub
/// published. The signature proves who made it: the new app must satisfy the
/// running app's own designated requirement, which pins the exact certificate it
/// was signed with. Only whoever holds that certificate's private key can pass —
/// a compromised GitHub account alone cannot.
enum UpdateVerifier {
    enum Failure: LocalizedError, Equatable {
        case missingChecksum
        case checksumMismatch
        case unreadableApp
        case notSigned
        case signedBySomeoneElse
        case wrongApp
        case wrongVersion(expected: String, found: String)

        var errorDescription: String? {
            switch self {
            case .missingChecksum:
                "GitHub gave no checksum for the download, so it cannot be verified."
            case .checksumMismatch:
                "The download is not the file that was published. It may have been damaged or altered."
            case .unreadableApp:
                "The download does not contain a Mac-Monologue app."
            case .notSigned:
                "The downloaded app is not signed."
            case .signedBySomeoneElse:
                "The downloaded app is not signed by the developer of this one."
            case .wrongApp:
                "The download contains a different app."
            case .wrongVersion(let expected, let found):
                "The download is version \(found), but \(expected) was expected."
            }
        }
    }

    // MARK: - Checksum

    /// Lowercase hex SHA-256, read in chunks so a large file never sits in memory.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verifyChecksum(of url: URL, expected: String?) throws {
        guard let expected, !expected.isEmpty else { throw Failure.missingChecksum }
        guard try sha256(of: url) == expected.lowercased() else { throw Failure.checksumMismatch }
    }

    // MARK: - Signature

    /// The rule the running app's signature satisfies — for a release build,
    /// "this bundle identifier, signed by this certificate".
    static func ownDesignatedRequirement() throws -> SecRequirement {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement
        else { throw Failure.notSigned }
        return requirement
    }

    /// The designated requirement of an app on disk.
    static func designatedRequirement(ofAppAt url: URL) throws -> SecRequirement {
        let staticCode = try staticCode(at: url)
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { throw Failure.notSigned }
        return requirement
    }

    /// Passes only if the app's signature is intact, covers everything inside it,
    /// and satisfies `requirement`.
    static func verifySignature(ofAppAt url: URL, matching requirement: SecRequirement) throws {
        let staticCode = try staticCode(at: url)

        // Intact at all? An unsigned app fails here, not as "someone else".
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidityWithErrors(staticCode, flags, nil, nil) == errSecSuccess else {
            throw Failure.notSigned
        }
        guard SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, nil) == errSecSuccess else {
            throw Failure.signedBySomeoneElse
        }
    }

    private static func staticCode(at url: URL) throws -> SecStaticCode {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { throw Failure.unreadableApp }
        return staticCode
    }

    // MARK: - Identity

    /// The same app, and the version the release claims to be — so a mix-up can
    /// never install a different app or quietly go backwards.
    static func verifyBundle(at url: URL, identifier: String, version: AppVersion) throws {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) else {
            throw Failure.unreadableApp
        }
        guard info["CFBundleIdentifier"] as? String == identifier else { throw Failure.wrongApp }
        let found = (info["CFBundleShortVersionString"] as? String) ?? "?"
        guard AppVersion(found) == version else {
            throw Failure.wrongVersion(expected: version.description, found: found)
        }
    }
}
