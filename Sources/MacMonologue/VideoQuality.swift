import Foundation

/// How hard a take is compressed, in four steps a user can judge by file size.
///
/// Fixed bitrates rather than quality-based control, so the size a step promises
/// is the size you get: "High" stays under 100 MB for ten minutes.
enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case economical
    case medium
    case high
    case veryHigh

    static let standard: VideoQuality = .medium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .economical: "Economical"
        case .medium: "Medium"
        case .high: "High"
        case .veryHigh: "Very high"
        }
    }

    /// What the step means in practice, for someone who does not think in pixels.
    var explanation: String {
        switch self {
        case .economical:
            "Small files, easy to email or upload on a slow connection. Small text on a screen looks a little soft."
        case .medium:
            "The all-rounder: sharp enough for slides and faces, small enough to share anywhere."
        case .high:
            "Crisp text and detail, still easy to share as a link."
        case .veryHigh:
            "The best picture, for editing afterwards or showing on a big screen. Large files."
        }
    }

    /// Long edge a screen recording is scaled to.
    var screenLongEdge: Int {
        switch self {
        case .economical: 1280
        case .medium, .high: 1920
        case .veryHigh: ScreenCanvas.longEdge
        }
    }

    /// Long edge a camera recording is scaled to; nil keeps the camera's own size.
    var cameraLongEdge: Int? {
        switch self {
        case .economical: 1280
        case .medium, .high: 1920
        case .veryHigh: nil
        }
    }

    var videoBitRate: Int {
        switch self {
        case .economical: 350_000
        case .medium: 700_000
        case .high: 1_180_000
        case .veryHigh: 4_000_000
        }
    }

    var audioBitRate: Int {
        switch self {
        case .economical: 64_000
        case .medium: 96_000
        case .high, .veryHigh: 128_000
        }
    }

    /// Picture and sound together, in megabytes (10⁶ bytes, as Finder counts).
    func estimatedMegabytes(minutes: Double) -> Double {
        Double(videoBitRate + audioBitRate) * minutes * 60 / 8 / 1_000_000
    }

    /// "≈ 60 MB per 10 min", rounded to what the estimate can honestly claim.
    var sizeLabel: String {
        let megabytes = estimatedMegabytes(minutes: 10)
        let rounded = megabytes < 100 ? (megabytes / 5).rounded() * 5 : (megabytes / 10).rounded() * 10
        return "≈ \(Int(rounded)) MB per 10 min"
    }

    /// The size a camera frame of `width` × `height` is written at.
    func cameraSize(width: Int, height: Int) -> (width: Int, height: Int) {
        ScreenCanvas.size(forDisplayWidth: width, height: height,
                          longEdge: cameraLongEdge ?? max(width, height))
    }
}
