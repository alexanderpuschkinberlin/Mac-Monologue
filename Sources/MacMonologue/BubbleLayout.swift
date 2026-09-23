import CoreGraphics
import Foundation

enum BubbleCorner: String, CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var isTop: Bool { self == .topLeading || self == .topTrailing }
    var isLeading: Bool { self == .topLeading || self == .bottomLeading }

    var accessibilityLabel: String {
        switch self {
        case .topLeading: "Top left"
        case .topTrailing: "Top right"
        case .bottomLeading: "Bottom left"
        case .bottomTrailing: "Bottom right"
        }
    }
}

enum BubbleSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    /// Diameter as a share of the canvas height.
    var fractionOfCanvasHeight: CGFloat {
        switch self {
        case .small: 0.16
        case .medium: 0.22
        case .large: 0.30
        }
    }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

/// Where the camera bubble sits on the recorded canvas.
///
/// The one function both the recording and the live preview use to place the
/// bubble, which is what guarantees the preview shows where it will land.
struct BubbleLayout: Equatable, Sendable {
    var corner: BubbleCorner = .bottomTrailing
    var size: BubbleSize = .medium

    /// Distance from the canvas edges, as a share of the canvas height.
    static let marginFraction: CGFloat = 0.03

    /// The bubble in pixels, origin top-left. Always a square — the bubble is a
    /// circle inscribed in it — and always wholly inside the canvas.
    func frame(canvasWidth: Int, canvasHeight: Int) -> CGRect {
        let width = CGFloat(canvasWidth)
        let height = CGFloat(canvasHeight)
        let margin = (height * Self.marginFraction).rounded()

        let largestThatFits = max(0, min(width, height) - margin * 2)
        let diameter = min((height * size.fractionOfCanvasHeight).rounded(), largestThatFits)

        let x = corner.isLeading ? margin : width - margin - diameter
        let y = corner.isTop ? margin : height - margin - diameter
        return CGRect(x: x, y: y, width: diameter, height: diameter)
    }

    /// The same frame as fractions of the canvas, origin top-left, for placing the
    /// bubble over a preview of any size.
    func normalizedFrame(canvasWidth: Int, canvasHeight: Int) -> CGRect {
        let frame = frame(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        let width = CGFloat(max(1, canvasWidth))
        let height = CGFloat(max(1, canvasHeight))
        return CGRect(x: frame.minX / width, y: frame.minY / height,
                      width: frame.width / width, height: frame.height / height)
    }
}
