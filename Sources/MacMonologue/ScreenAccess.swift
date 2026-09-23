import AppKit
import CoreGraphics
import Foundation

/// Whether the app may record the screen. Deliberately separate from
/// `RecorderState`: the camera can be perfectly usable while screen access is not.
enum ScreenAccessState: Equatable, Sendable {
    case unknown
    case granted
    /// Never granted, or refused. macOS asks exactly once; after that the user has
    /// to switch it on in System Settings.
    case denied
    /// Granted in System Settings, but this running copy of the app cannot see the
    /// screen yet — macOS only applies it to a freshly started process.
    case needsRelaunch
}

enum ScreenAccess {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; does nothing once answered.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    /// Starts a fresh copy of the app and quits this one, which is what makes a
    /// newly granted screen recording permission take effect.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
