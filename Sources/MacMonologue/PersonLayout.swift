import CoreGraphics
import Foundation

/// How the person is cut out in Screen + Green Screen: by the green behind
/// them, by Apple's person segmentation, or whichever fits.
enum KeyingChoice: String, CaseIterable, Sendable {
    case automatic
    case greenScreen
    case segmentation

    var label: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .greenScreen: String(localized: "Green screen")
        case .segmentation: String(localized: "No green screen")
        }
    }
}

/// Where the cut-out person stands on the recorded canvas: a centre and a
/// height, both as shares of the canvas, so they hold for any screen size.
///
/// The one function both the recording and the preview's drag handle use to
/// place the person, as `BubbleLayout` is for the bubble.
struct PersonLayout: Equatable, Sendable {
    /// Centre of the camera picture, normalised, origin top-left.
    var center = CGPoint(x: 0.8, y: 0.78)
    /// Height of the camera picture as a share of the canvas height.
    var height: CGFloat = 0.6

    static let heightRange: ClosedRange<CGFloat> = 0.25...1
    /// At least this much of the picture stays on the canvas, both ways.
    static let minimumVisible: CGFloat = 0.25

    /// The whole camera picture in pixels, origin top-left. It may reach past
    /// the edges - cut off at the bottom is the weather-map look - but never
    /// more than `1 - minimumVisible` of it.
    func frame(canvasWidth: Int, canvasHeight: Int, cameraAspect: CGFloat) -> CGRect {
        let canvas = CGSize(width: CGFloat(canvasWidth), height: CGFloat(canvasHeight))
        let h = (canvas.height * min(Self.heightRange.upperBound, max(Self.heightRange.lowerBound, height))).rounded()
        let w = (h * max(0.1, cameraAspect)).rounded()
        var x = center.x * canvas.width - w / 2
        var y = center.y * canvas.height - h / 2
        x = min(canvas.width - w * Self.minimumVisible, max(-w * (1 - Self.minimumVisible), x))
        y = min(canvas.height - h * Self.minimumVisible, max(-h * (1 - Self.minimumVisible), y))
        return CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)
    }

    /// The same frame as shares of the canvas, for placing the handle over a
    /// preview of any size.
    func normalizedFrame(canvasWidth: Int, canvasHeight: Int, cameraAspect: CGFloat) -> CGRect {
        let frame = frame(canvasWidth: canvasWidth, canvasHeight: canvasHeight, cameraAspect: cameraAspect)
        let width = CGFloat(max(1, canvasWidth)), height = CGFloat(max(1, canvasHeight))
        return CGRect(x: frame.minX / width, y: frame.minY / height,
                      width: frame.width / width, height: frame.height / height)
    }

    /// This layout with its centre where the frame actually ends up, so a drag
    /// past the limits does not store a position the picture cannot reach.
    func clamped(canvasWidth: Int, canvasHeight: Int, cameraAspect: CGFloat) -> PersonLayout {
        let frame = normalizedFrame(canvasWidth: canvasWidth, canvasHeight: canvasHeight, cameraAspect: cameraAspect)
        var copy = self
        copy.center = CGPoint(x: frame.midX, y: frame.midY)
        copy.height = min(Self.heightRange.upperBound, max(Self.heightRange.lowerBound, height))
        return copy
    }
}
