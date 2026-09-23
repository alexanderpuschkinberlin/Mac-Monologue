import Foundation

/// The size a screen is recorded at.
enum ScreenCanvas {
    /// Long edge in pixels. At 2560, slide text and code stay legible — at 1920
    /// small type visibly smears — while the file stays a fraction of native Retina.
    static let longEdge = 2560

    /// Scales so the long edge is `longEdge`, keeping the aspect ratio.
    ///
    /// Never scales up: a small display is recorded at its own size. Both edges are
    /// rounded down to even numbers, which 4:2:0 video requires.
    static func size(forDisplayWidth width: Int, height: Int, longEdge: Int = longEdge) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (2, 2) }
        let scale = min(1, Double(longEdge) / Double(max(width, height)))
        func even(_ value: Double) -> Int { max(2, Int(value.rounded()) & ~1) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }
}
