import CoreImage
import Foundation

/// The arithmetic of a green screen, per colour: how much of a pixel is
/// background, and how to take the green glow off what is not. Pure, so the
/// rules are tested on numbers; `PersonKeyer` bakes them into colour cubes the
/// GPU applies to every frame.
enum ChromaKey {
    /// How far green must stand above the stronger of red and blue before a
    /// pixel starts to count as background, and where it is background fully.
    /// Between the two the edge is soft - hair and motion blur fade, not step.
    static let dominanceStart: Double = 0.07
    static let dominanceFull: Double = 0.22

    /// Green's lead over red and blue: 0 for greys, skin, white; high for a screen.
    static func dominance(r: Double, g: Double, b: Double) -> Double {
        max(0, g - max(r, b))
    }

    /// 1 for the person, 0 for the green behind them.
    static func alpha(r: Double, g: Double, b: Double) -> Double {
        let d = dominance(r: r, g: g, b: b)
        let t = min(1, max(0, (d - dominanceStart) / (dominanceFull - dominanceStart)))
        let smooth = t * t * (3 - 2 * t)
        return 1 - smooth
    }

    /// Green light bouncing off the screen tints hair and edges; capping green at
    /// the stronger of red and blue takes the tint off and leaves other colours be.
    static func despill(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        (r, min(g, max(r, b)), b)
    }

    // MARK: - Cubes

    static let cubeSize = 32

    /// A cube whose output is the alpha as grey: the mask.
    static func maskCube() -> Data { cube { r, g, b in let a = alpha(r: r, g: g, b: b); return (a, a, a) } }

    /// A cube that takes the green spill off the colours.
    static func despillCube() -> Data { cube { r, g, b in despill(r: r, g: g, b: b) } }

    /// RGBA float cube in the order Core Image expects: red fastest, blue slowest.
    private static func cube(_ map: (Double, Double, Double) -> (Double, Double, Double)) -> Data {
        let size = cubeSize
        var values = [Float](repeating: 0, count: size * size * size * 4)
        var index = 0
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let step = Double(size - 1)
                    let out = map(Double(r) / step, Double(g) / step, Double(b) / step)
                    values[index] = Float(out.0)
                    values[index + 1] = Float(out.1)
                    values[index + 2] = Float(out.2)
                    values[index + 3] = 1
                    index += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

/// Decides, from the edges of the camera picture, whether there is a green
/// screen behind the person. With a hysteresis, so a green shirt moving through
/// the edge does not flip the picture between the two ways of cutting out.
struct GreenScreenDetector {
    static let switchOn = 0.6
    static let switchOff = 0.4

    private(set) var isGreen = false

    /// A pixel that clearly belongs to a green screen.
    static func isScreenGreen(r: Double, g: Double, b: Double) -> Bool {
        ChromaKey.dominance(r: r, g: g, b: b) > 0.12 && g > 0.25
    }

    static func greenShare(_ pixels: [(r: Double, g: Double, b: Double)]) -> Double {
        guard !pixels.isEmpty else { return 0 }
        return Double(pixels.filter { isScreenGreen(r: $0.r, g: $0.g, b: $0.b) }.count) / Double(pixels.count)
    }

    /// The border samples of one frame; returns whether to key by colour.
    @discardableResult
    mutating func observe(_ pixels: [(r: Double, g: Double, b: Double)]) -> Bool {
        let share = Self.greenShare(pixels)
        if isGreen, share < Self.switchOff { isGreen = false }
        if !isGreen, share > Self.switchOn { isGreen = true }
        return isGreen
    }
}
