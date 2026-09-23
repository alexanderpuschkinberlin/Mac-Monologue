import AVFoundation
import AppKit
import CoreGraphics

/// The three permissions the app can ask for, in one place, for Settings and
/// the welcome steps.
enum Permission: CaseIterable, Identifiable {
    case camera
    case microphone
    case screen

    enum Status { case granted, notAsked, denied }

    var id: Self { self }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .screen: "Screen recording"
        }
    }

    var status: Status {
        switch self {
        case .camera: Self.status(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: Self.status(AVCaptureDevice.authorizationStatus(for: .audio))
        // macOS does not say whether it has asked already; "not yet" covers both.
        case .screen: CGPreflightScreenCaptureAccess() ? .granted : .notAsked
        }
    }

    /// Asks macOS. Returns whether it is granted now — for screen recording that
    /// is often only true after a restart.
    func request() async -> Bool {
        switch self {
        case .camera: await AVCaptureDevice.requestAccess(for: .video)
        case .microphone: await AVCaptureDevice.requestAccess(for: .audio)
        case .screen: CGRequestScreenCaptureAccess()
        }
    }

    var settingsURL: URL {
        let pane = switch self {
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        case .screen: "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }

    @MainActor
    func openSettings() { NSWorkspace.shared.open(settingsURL) }

    private static func status(_ status: AVAuthorizationStatus) -> Status {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }
}
