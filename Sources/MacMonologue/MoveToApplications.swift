import AppKit
import Foundation

/// Offers to move the app into Applications when it was opened from somewhere
/// else — usually straight out of Downloads.
///
/// From there macOS runs it out of a read-only hiding place ("App
/// Translocation"), where no update can be installed; in Applications updates
/// work and the app is where people look for it.
@MainActor
enum MoveToApplications {
    enum MoveError: LocalizedError {
        case notWritable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notWritable:
                "Your Applications folder cannot be written to from this account."
            case .failed(let detail):
                detail
            }
        }
    }

    static let destination = URL(fileURLWithPath: "/Applications/Mac-Monologue.app")

    /// Asks, if the app is not in an Applications folder. Returns true when it is
    /// being moved and about to relaunch — the caller should do nothing more.
    @discardableResult
    static func offerIfNeeded(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        guard shouldOffer(bundleURL: bundleURL) else { return false }

        let alert = NSAlert()
        alert.messageText = "Move Mac-Monologue to your Applications folder?"
        alert.informativeText = "It is running from \(folderName(of: bundleURL)). Updates can only be "
            + "installed in Applications, and it is easy to find there. It opens again right away."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            DevicePreferences.declinedMoveVersion = AppVersion.current?.description
            return false
        }

        do {
            try move(from: bundleURL)
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "Mac-Monologue could not be moved"
            failure.informativeText = "\(error.localizedDescription) Drag Mac-Monologue into the "
                + "Applications folder in Finder instead."
            failure.runModal()
            return false
        }
        Relauncher.relaunch(at: destination)
        return true
    }

    static func shouldOffer(bundleURL: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        // Development builds and the update test's copies live under build/.
        if SelfTest.isEnabled || PreviewHost.isActive || path.contains("/build/") { return false }
        if path.hasPrefix("/Applications/") { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home + "/Applications/") { return false }
        if let declined = DevicePreferences.declinedMoveVersion,
           declined == AppVersion.current?.description { return false }
        return true
    }

    /// Copies the running app into Applications, replacing an older copy in one
    /// step, and puts the original in the Trash.
    static func move(from bundleURL: URL, to destination: URL = destination,
                     trashingOriginal: Bool = true) throws {
        let folder = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else { throw MoveError.notWritable }

        let staging = folder.appendingPathComponent(".Mac-Monologue-\(UUID().uuidString).app")
        do {
            try FileManager.default.copyItem(at: bundleURL, to: staging)
            // The user has just opened it with "Open Anyway"; the copy should not
            // ask again.
            removeQuarantine(from: staging)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw MoveError.failed(error.localizedDescription)
        }

        // The original, not the read-only translocated copy macOS runs.
        if trashingOriginal, let original = originalLocation(of: bundleURL), original != destination {
            try? FileManager.default.trashItem(at: original, resultingItemURL: nil)
        }
    }

    private static func removeQuarantine(from app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", app.path]
        try? process.run()
        process.waitUntilExit()
    }

    /// Where the app really is. Under App Translocation, macOS runs it from a
    /// random read-only path; Security can say where it came from.
    static func originalLocation(of bundleURL: URL) -> URL? {
        guard bundleURL.path.contains("/AppTranslocation/") else { return bundleURL }
        typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?)
            -> Unmanaged<CFURL>?
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let original = unsafeBitCast(symbol, to: Original.self)
        return original(bundleURL as CFURL, nil)?.takeRetainedValue() as URL?
    }

    private static func folderName(of bundleURL: URL) -> String {
        let folder = (originalLocation(of: bundleURL) ?? bundleURL).deletingLastPathComponent()
        return folder.lastPathComponent == "Downloads" ? "your Downloads folder" : "“\(folder.lastPathComponent)”"
    }
}
