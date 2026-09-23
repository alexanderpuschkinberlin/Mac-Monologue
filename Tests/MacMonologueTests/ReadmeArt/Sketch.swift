import SwiftUI

// A tiny hand-drawn-look toolkit for the README illustrations.
//
// Lines are split into short pieces, their points nudged a little off the true
// line, and every shape drawn twice with different nudges — the doubled,
// slightly wandering stroke of a pen. The randomness is seeded, so rendering
// again produces the same images, byte for byte, and Git sees no change.

/// SplitMix64: small, fast, and the same sequence for the same seed everywhere.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func jitter(_ amount: CGFloat) -> CGFloat {
        CGFloat.random(in: -amount...amount, using: &self)
    }
}

/// Ink for one colour scheme: black on light pages, near-white on dark ones,
/// and the recording red as the one accent.
struct Ink {
    let line: Color
    let soft: Color
    let accent: Color
    /// A translucent hand reads much heavier on white than on a dark page.
    var handOpacity: Double = 0.18

    static func forScheme(_ scheme: ColorScheme) -> Ink {
        scheme == .dark
            ? Ink(line: Color(white: 0.93), soft: Color(white: 0.93).opacity(0.45),
                  accent: Color(red: 1.0, green: 0.36, blue: 0.37), handOpacity: 0.2)
            : Ink(line: Color(white: 0.11), soft: Color(white: 0.11).opacity(0.4),
                  accent: Color(red: 0.90, green: 0.23, blue: 0.25), handOpacity: 0.11)
    }
}

enum Hand {
    static func bold(_ size: CGFloat) -> Font { .custom("Noteworthy-Bold", size: size) }
    static func light(_ size: CGFloat) -> Font { .custom("Noteworthy-Light", size: size) }
}

/// Everything is drawn through this: it owns the random sequence, so the order
/// of drawing calls is what makes an image reproducible.
struct Sketcher {
    var context: GraphicsContext
    var random: SeededRandom
    var ink: Ink

    init(_ context: GraphicsContext, seed: UInt64, scheme: ColorScheme) {
        self.context = context
        self.random = SeededRandom(seed)
        self.ink = Ink.forScheme(scheme)
    }

    // MARK: - Strokes

    /// A wandering line through `points`, drawn twice.
    mutating func stroke(_ points: [CGPoint], closed: Bool = false, color: Color? = nil,
                         width: CGFloat = 2.2, wobble: CGFloat = 1.3) {
        let shading = GraphicsContext.Shading.color(color ?? ink.line)
        for pass in 0..<2 {
            let path = roughPath(points, closed: closed, wobble: wobble * (pass == 0 ? 1 : 1.4))
            context.stroke(path, with: shading,
                           style: StrokeStyle(lineWidth: pass == 0 ? width : width * 0.55,
                                              lineCap: .round, lineJoin: .round))
        }
    }

    mutating func line(_ from: CGPoint, _ to: CGPoint, color: Color? = nil, width: CGFloat = 2.2) {
        stroke([from, to], color: color, width: width)
    }

    mutating func rect(_ rect: CGRect, radius: CGFloat = 8, color: Color? = nil, width: CGFloat = 2.2) {
        stroke(Self.roundedRectPoints(rect, radius: radius), closed: true, color: color, width: width)
    }

    /// A circle that, like one drawn by hand, does not quite meet itself.
    mutating func ellipse(_ rect: CGRect, color: Color? = nil, width: CGFloat = 2.2) {
        let start = CGFloat.random(in: 0...(2 * .pi), using: &random)
        let overshoot: CGFloat = 0.22
        let points = stride(from: 0, through: 2 * .pi + overshoot, by: .pi / 24).map { angle in
            CGPoint(x: rect.midX + cos(start + angle) * rect.width / 2,
                    y: rect.midY + sin(start + angle) * rect.height / 2)
        }
        stroke(points, color: color, width: width, wobble: 1.0)
    }

    /// A curved arrow, head included.
    mutating func arrow(from: CGPoint, to: CGPoint, bend: CGFloat = 0.25, color: Color? = nil) {
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let normal = CGPoint(x: -(to.y - from.y) * bend, y: (to.x - from.x) * bend)
        let control = CGPoint(x: mid.x + normal.x, y: mid.y + normal.y)
        let points = stride(from: 0.0, through: 1.0, by: 0.05).map { t -> CGPoint in
            let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
            return CGPoint(x: a * from.x + b * control.x + c * to.x, y: a * from.y + b * control.y + c * to.y)
        }
        stroke(points, color: color, width: 2)

        let angle = atan2(to.y - control.y, to.x - control.x)
        for side in [-1.0, 1.0] {
            let head = CGPoint(x: to.x - cos(angle + side * 0.5) * 14, y: to.y - sin(angle + side * 0.5) * 14)
            stroke([head, to], color: color, width: 2)
        }
    }

    /// Diagonal hatching inside `shape`, the pen's way of filling.
    mutating func hatch(_ shape: Path, bounds: CGRect, spacing: CGFloat = 7, color: Color? = nil) {
        var clipped = context
        clipped.clip(to: shape)
        let color = color ?? ink.line
        var x = bounds.minX - bounds.height
        while x < bounds.maxX {
            let from = CGPoint(x: x, y: bounds.maxY)
            let to = CGPoint(x: x + bounds.height, y: bounds.minY)
            let path = roughPath([from, to], closed: false, wobble: 0.8)
            clipped.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            x += spacing
        }
    }

    /// A circle drawn as dashes: a place something could go.
    mutating func dashedEllipse(_ rect: CGRect, color: Color? = nil, width: CGFloat = 1.8) {
        let dashes = 14
        for index in 0..<dashes {
            let from = CGFloat(index) / CGFloat(dashes) * 2 * .pi
            let to = from + .pi / CGFloat(dashes) * 1.1
            let points = stride(from: from, through: to, by: 0.08).map {
                CGPoint(x: rect.midX + cos($0) * rect.width / 2, y: rect.midY + sin($0) * rect.height / 2)
            }
            stroke(points, color: color, width: width, wobble: 0.5)
        }
    }

    /// Head and shoulders, cropped to a circle — the person in a bubble.
    mutating func person(in bubble: CGRect, width: CGFloat = 2) {
        let outside = context
        context.clip(to: Path(ellipseIn: bubble.insetBy(dx: 3, dy: 3)))
        let unit = bubble.width / 118
        ellipse(CGRect(x: bubble.midX - 18 * unit, y: bubble.minY + 24 * unit, width: 36 * unit, height: 40 * unit),
                width: width)
        stroke([CGPoint(x: bubble.midX - 58 * unit, y: bubble.maxY + 6 * unit),
                CGPoint(x: bubble.midX - 34 * unit, y: bubble.midY + 26 * unit),
                CGPoint(x: bubble.midX, y: bubble.midY + 20 * unit),
                CGPoint(x: bubble.midX + 34 * unit, y: bubble.midY + 26 * unit),
                CGPoint(x: bubble.midX + 58 * unit, y: bubble.maxY + 6 * unit)], width: width)
        context = outside
    }

    mutating func check(at point: CGPoint, size: CGFloat = 16, color: Color? = nil) {
        stroke([CGPoint(x: point.x - size / 2, y: point.y),
                CGPoint(x: point.x - size / 6, y: point.y + size / 2.5),
                CGPoint(x: point.x + size / 2, y: point.y - size / 2)], color: color ?? ink.accent, width: 2.6, wobble: 0.6)
    }

    // MARK: - Text

    mutating func text(_ string: String, at point: CGPoint, font: Font, color: Color? = nil,
                       anchor: UnitPoint = .center, angle: Angle = .zero, mirrored: Bool = false) {
        var local = context
        local.translateBy(x: point.x, y: point.y)
        local.rotate(by: angle)
        if mirrored { local.scaleBy(x: -1, y: 1) }
        local.draw(Text(string).font(font).foregroundStyle(color ?? ink.line), at: .zero, anchor: anchor)
    }

    // MARK: - Geometry

    private mutating func roughPath(_ points: [CGPoint], closed: Bool, wobble: CGFloat) -> Path {
        var dense: [CGPoint] = []
        let segments = closed ? points + [points[0]] : points
        for index in 0..<(segments.count - 1) {
            let a = segments[index], b = segments[index + 1]
            let length = hypot(b.x - a.x, b.y - a.y)
            let steps = max(1, Int(length / 26))
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                dense.append(CGPoint(x: a.x + (b.x - a.x) * t + random.jitter(wobble),
                                     y: a.y + (b.y - a.y) * t + random.jitter(wobble)))
            }
        }
        dense.append(CGPoint(x: segments.last!.x + random.jitter(wobble),
                             y: segments.last!.y + random.jitter(wobble)))

        // Smoothed through the midpoints, so the wobble reads as a hand, not noise.
        var path = Path()
        path.move(to: dense[0])
        for index in 1..<dense.count - 1 {
            let mid = CGPoint(x: (dense[index].x + dense[index + 1].x) / 2,
                              y: (dense[index].y + dense[index + 1].y) / 2)
            path.addQuadCurve(to: mid, control: dense[index])
        }
        path.addLine(to: dense[dense.count - 1])
        return path
    }

    static func roundedRectPoints(_ rect: CGRect, radius r: CGFloat) -> [CGPoint] {
        func arc(_ cx: CGFloat, _ cy: CGFloat, _ from: CGFloat) -> [CGPoint] {
            stride(from: from, through: from + .pi / 2, by: .pi / 8).map {
                CGPoint(x: cx + cos($0) * r, y: cy + sin($0) * r)
            }
        }
        return arc(rect.maxX - r, rect.minY + r, -.pi / 2)
            + arc(rect.maxX - r, rect.maxY - r, 0)
            + arc(rect.minX + r, rect.maxY - r, .pi / 2)
            + arc(rect.minX + r, rect.minY + r, .pi)
    }
}
