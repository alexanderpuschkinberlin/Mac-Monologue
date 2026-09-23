import Foundation

/// What a take records: the camera on its own, or a screen with the camera as a
/// round bubble in one corner.
enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case camera
    case screenAndCamera

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camera: "Camera"
        case .screenAndCamera: "Screen + Camera"
        }
    }
}
