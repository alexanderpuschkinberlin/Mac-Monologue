import CoreGraphics

/// Keeps a face in frame by moving a zoomed-in window over the camera's picture,
/// for cameras without Center Stage.
///
/// Faces are found a few times a second; the window glides towards them every
/// frame. A dead zone ignores small movements — talking, nodding — so the
/// picture only moves when you actually move, and never jitters.
///
/// All rects are normalised to the frame, origin top-left.
struct FaceFraming: Equatable {
    /// How far the window zooms in. More keeps a moving person better in frame
    /// but costs sharpness: at 1.4, a 1080p camera is recorded from ~1370 × 770.
    static let zoom: CGFloat = 1.4
    /// How far the face may drift from where the window is aiming before it follows.
    static let deadZone: CGFloat = 0.05
    /// Share of the remaining way covered per frame: about a second to settle at 30 fps.
    static let glide: CGFloat = 0.1
    /// Faces sit a little above the middle, where a camera operator would put them.
    static let headroom: CGFloat = 0.12

    static var windowSize: CGSize { CGSize(width: 1 / zoom, height: 1 / zoom) }

    private(set) var center = CGPoint(x: 0.5, y: 0.5)
    private(set) var target = CGPoint(x: 0.5, y: 0.5)

    /// The window, as it stands.
    var crop: CGRect {
        let size = Self.windowSize
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// A new sighting. Nil — no face — leaves the window where it is: someone
    /// who leans out of the picture should find it waiting when they come back.
    mutating func observe(face: CGRect?) {
        guard let face, face.width > 0, face.height > 0 else { return }
        let aim = Self.clamped(CGPoint(x: face.midX,
                                       y: face.midY + Self.windowSize.height * Self.headroom))
        if hypot(aim.x - target.x, aim.y - target.y) > Self.deadZone {
            target = aim
        }
    }

    /// One frame on: moves the window part of the way to the target.
    mutating func step() -> CGRect {
        center.x += (target.x - center.x) * Self.glide
        center.y += (target.y - center.y) * Self.glide
        return crop
    }

    /// Keeps the window inside the picture.
    static func clamped(_ point: CGPoint) -> CGPoint {
        let half = CGSize(width: windowSize.width / 2, height: windowSize.height / 2)
        return CGPoint(x: min(max(point.x, half.width), 1 - half.width),
                       y: min(max(point.y, half.height), 1 - half.height))
    }
}
