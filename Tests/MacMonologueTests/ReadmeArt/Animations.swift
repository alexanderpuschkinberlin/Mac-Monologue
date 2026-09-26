import SwiftUI
@testable import Mac_Monologue

/// A drawing that moves: the same pen as the stills, given a time.
///
/// The seed changes every `boilFrames` frames, so standing lines are redrawn a
/// few times a second with fresh wobble - the "boil" of a hand-drawn cartoon -
/// while things that move are placed by the time alone and move smoothly.
struct AnimatedMotif {
    let name: String
    let size: CGSize
    let seed: UInt64
    let duration: Double
    let fps: Double
    var boilFrames = 3
    let draw: (inout Sketcher, CGSize, Double) -> Void

    var frameCount: Int { Int((duration * fps).rounded()) }
}

struct AnimatedFrameView: View {
    let motif: AnimatedMotif
    let frame: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            var sketch = Sketcher(context, seed: motif.seed &+ UInt64(frame / motif.boilFrames), scheme: scheme)
            motif.draw(&sketch, size, Double(frame) / motif.fps)
        }
        .frame(width: motif.size.width, height: motif.size.height)
    }
}

@MainActor
enum ReadmeAnimations {
    static let all: [AnimatedMotif] = [touchCut]

    /// Touch Cut from the user's side: a finger lands on the trackpad and the
    /// picture cuts to the screen; it lifts, the 0.7 s hold runs out as a ring,
    /// and the picture cuts back to you. No words, so it suits every language.
    /// It starts and ends on you, full frame - the page leaves it there.
    static let touchCut = AnimatedMotif(name: "touch-cut-anim", size: CGSize(width: 440, height: 300),
                                        seed: 60, duration: 6, fps: 24) { s, _, t in
        let screen = CGRect(x: 80, y: 16, width: 280, height: 178)
        let pad = CGRect(x: 160, y: 222, width: 120, height: 66)
        let contact = CGPoint(x: pad.midX, y: pad.midY + 8)

        let down = 1.3, up = 3.4, hold = 0.7          // the app's own AutoCut.holdSeconds
        let showsScreen = t >= down && t < up + hold

        func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }

        // The picture: you, full frame - or the slide with you in the bubble.
        if showsScreen {
            s.rect(screen, radius: 10, width: 2.4)
            // Lines appear one after another, as if presenting.
            for (index, width) in [118.0, 150.0, 92.0].enumerated() {
                let appear = down + 0.2 + Double(index) * 0.6
                let grow = CGFloat(ease((t - appear) / 0.35))
                guard grow > 0 else { continue }
                let y = screen.minY + 42 + CGFloat(index) * 30
                s.line(CGPoint(x: screen.minX + 24, y: y), CGPoint(x: screen.minX + 24 + width * grow, y: y), width: 2)
            }
            let bubble = CGRect(x: screen.maxX - 70, y: screen.maxY - 70, width: 58, height: 58)
            s.context.fill(Path(ellipseIn: bubble), with: .color(s.ink.line.opacity(0.06)))
            s.ellipse(bubble, width: 2.2)
            s.person(in: bubble, width: 1.6)
        } else {
            s.context.fill(Path(roundedRect: screen, cornerRadius: 10), with: .color(s.ink.line.opacity(0.06)))
            let outside = s.context
            s.context.clip(to: Path(roundedRect: screen.insetBy(dx: 3, dy: 3), cornerRadius: 8))
            s.ellipse(CGRect(x: screen.midX - 26, y: screen.minY + 26, width: 52, height: 62), width: 2.2)
            s.stroke([CGPoint(x: screen.midX - 110, y: screen.maxY + 10), CGPoint(x: screen.midX - 62, y: screen.minY + 120),
                      CGPoint(x: screen.midX, y: screen.minY + 108), CGPoint(x: screen.midX + 62, y: screen.minY + 120),
                      CGPoint(x: screen.midX + 110, y: screen.maxY + 10)], width: 2.2)
            s.context = outside
            s.rect(screen, radius: 10, width: 2.4)
        }

        // The cut: scissors flash between trackpad and picture.
        for cut in [down, up + hold] where t >= cut && t < cut + 0.35 {
            s.text("✂", at: CGPoint(x: pad.minX - 26, y: pad.minY - 10), font: .system(size: 22), color: s.ink.accent)
        }

        // The trackpad.
        s.rect(pad, radius: 10, width: 2)

        // The finger, from below: comes in, rests and moves a little, leaves.
        let tip: CGPoint?
        switch t {
        case (down - 0.6)..<down:
            let k = CGFloat(ease((t - (down - 0.6)) / 0.6))
            tip = CGPoint(x: contact.x, y: contact.y + (1 - k) * 90)
        case down..<up:
            // A slow swipe up and back, as when scrolling through a slide.
            let k = CGFloat(sin((t - down) / (up - down) * .pi))
            tip = CGPoint(x: contact.x, y: contact.y - 16 * k)
        case up..<(up + 0.35):
            let k = CGFloat(ease((t - up) / 0.35))
            tip = CGPoint(x: contact.x, y: contact.y + k * 90)
        default:
            tip = nil
        }
        if let tip {
            let finger = Path(roundedRect: CGRect(x: tip.x - 13, y: tip.y - 13, width: 26, height: 120), cornerRadius: 13)
            s.context.fill(finger, with: .color(s.ink.line.opacity(s.ink.handOpacity)))
            s.context.stroke(finger, with: .color(s.ink.line.opacity(0.55)), lineWidth: 1.4)
            if t >= down && t < up {
                s.context.fill(Path(ellipseIn: CGRect(x: tip.x - 6, y: tip.y - 6, width: 12, height: 12)),
                               with: .color(s.ink.accent))
            }
        }

        // Landing: one ring spreads out.
        if t >= down && t < down + 0.4 {
            let k = CGFloat((t - down) / 0.4)
            let r = 10 + 20 * k
            s.context.stroke(Path(ellipseIn: CGRect(x: contact.x - r, y: contact.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(s.ink.accent.opacity(Double(1 - k))), lineWidth: 2)
        }

        // Lifted: the hold runs out as a ring closing clockwise, then the cut.
        if t >= up && t < up + hold + 0.25 {
            let k = min(1, (t - up) / hold)
            let fade = t > up + hold ? 1 - (t - up - hold) / 0.25 : 1
            var ring = Path()
            ring.addArc(center: contact, radius: 16, startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * k), clockwise: false)
            s.context.stroke(ring, with: .color(s.ink.accent.opacity(fade)),
                             style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
