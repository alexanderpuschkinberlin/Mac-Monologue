import Foundation

/// What a take records: the camera on its own, a screen on its own, a screen
/// with the camera as a round bubble in one corner, or that same picture cut to
/// the camera alone whenever no finger rests on the trackpad.
enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case camera
    case screen
    case screenAndCamera
    case screenAndCameraTouchCut
    case screenAndGreenScreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camera: "Camera"
        case .screen: "Screen"
        case .screenAndCamera: "Screen + Camera"
        case .screenAndCameraTouchCut: "Screen & Head Touch Cut"
        case .screenAndGreenScreen: "Screen + Green Screen"
        }
    }

    /// For the mode picker, whose segments are all as wide as the widest: the
    /// full name would squeeze everything beside it.
    var shortLabel: String {
        switch self {
        case .screenAndCameraTouchCut: "Touch Cut"
        case .screenAndGreenScreen: "Green Screen"
        default: label
        }
    }

    /// One sentence on what the mode records, for the mode picker's tooltip.
    var explanation: String {
        switch self {
        case .camera: String(localized: "Just you, through the camera.")
        case .screen: String(localized: "Just your screen.")
        case .screenAndCamera: String(localized: "Your screen, with you in a round bubble in a corner.")
        case .screenAndCameraTouchCut:
            String(localized: "Your screen while a finger rests on the trackpad, you in full frame once you let go.")
        case .screenAndGreenScreen: String(localized: "You, cut out, standing in front of your screen.")
        }
    }

    /// Whether a screen is captured: the canvas, the display picker, system audio.
    var recordsScreen: Bool { self != .camera }

    /// Whether the camera is part of the picture.
    var usesCamera: Bool { self != .screen }

    /// Whether the camera sits over the screen as a bubble, with a corner and a size.
    var showsBubble: Bool { self == .screenAndCamera || self == .screenAndCameraTouchCut }

    /// Whether the person is cut out and stands in front of the screen.
    var keysPerson: Bool { self == .screenAndGreenScreen }

    /// Whether the picture cuts to the camera alone while the trackpad is untouched.
    var cutsOnTouch: Bool { self == .screenAndCameraTouchCut }
}
