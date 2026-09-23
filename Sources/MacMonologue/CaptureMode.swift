import Foundation

/// What a take records: the camera on its own, a screen on its own, or a screen
/// with the camera as a round bubble in one corner.
enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case camera
    case screen
    case screenAndCamera

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camera: "Camera"
        case .screen: "Screen"
        case .screenAndCamera: "Screen + Camera"
        }
    }

    /// Whether a screen is captured: the canvas, the display picker, system audio.
    var recordsScreen: Bool { self != .camera }

    /// Whether the camera is part of the picture.
    var usesCamera: Bool { self != .screen }
}
