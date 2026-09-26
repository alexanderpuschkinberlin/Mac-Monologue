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
    static let all: [AnimatedMotif] = [hero, touchCut]

    /// The hero, as a take: recording starts, you pop into the corner and
    /// talk, the slide builds up. It ends exactly as the still - the clock at
    /// 02:14 - so the page rests on the familiar picture.
    static let hero = AnimatedMotif(name: "hero-anim", size: CGSize(width: 880, height: 470),
                                    seed: 70, duration: 6, fps: 24) { s, _, t in
        func ease(_ x: Double) -> CGFloat { let c = min(1, max(0, x)); return CGFloat(c * c * (3 - 2 * c)) }
        /// Past 1 and back, for things that pop in.
        func pop(_ x: Double) -> CGFloat {
            let c = min(1, max(0, x)) - 1
            return CGFloat(1 + 2.7 * c * c * c + 1.7 * c * c)
        }

        // Laptop
        let screen = CGRect(x: 70, y: 30, width: 560, height: 360)
        s.rect(screen, radius: 18, width: 2.6)
        s.rect(screen.insetBy(dx: 14, dy: 14), radius: 6, width: 1.4)
        s.stroke([CGPoint(x: 40, y: 392), CGPoint(x: 660, y: 392),
                  CGPoint(x: 700, y: 428), CGPoint(x: 0, y: 428)], closed: true, width: 2.6)
        s.line(CGPoint(x: 300, y: 392), CGPoint(x: 400, y: 392), width: 3)

        // Menu bar: recording starts, the dot breathes, the clock runs to 02:14.
        let bar = screen.minY + 44
        s.line(CGPoint(x: screen.minX + 16, y: bar), CGPoint(x: screen.maxX - 16, y: bar), width: 1.2)
        let recording = 0.6
        if t >= recording {
            let breathe = t < 5.5 ? 0.6 + 0.4 * cos((t - recording) * 2 * .pi / 1.2) : 1
            s.context.fill(Path(ellipseIn: CGRect(x: 512, y: bar - 26, width: 16, height: 16)),
                           with: .color(s.ink.accent.opacity(breathe)))
            let second = min(14, 8 + Int((t - recording) / 4.9 * 6))
            s.text(String(format: "02:%02d", second), at: CGPoint(x: 536, y: bar - 18), font: Hand.bold(18),
                   anchor: .leading)
        }

        // The slide builds up while you talk.
        let slide = CGRect(x: 112, y: 100, width: 330, height: 240)
        s.rect(slide, radius: 6, width: 1.8)
        s.text("Q3 plan", at: CGPoint(x: 132, y: 132), font: Hand.bold(28), anchor: .leading)
        for (index, width) in [150.0, 190.0, 120.0].enumerated() {
            let grow = ease((t - 2.2 - Double(index) * 0.6) / 0.35)
            guard grow > 0 else { continue }
            let y = 178 + CGFloat(index) * 30
            s.context.fill(Path(ellipseIn: CGRect(x: 136, y: y - 3, width: 6, height: 6)), with: .color(s.ink.line))
            s.line(CGPoint(x: 152, y: y), CGPoint(x: 152 + width * grow, y: y), width: 1.8)
        }
        for (index, height) in [36.0, 58.0, 82.0].enumerated() {
            let grow = ease((t - 3.9 - Double(index) * 0.25) / 0.45)
            guard grow > 0 else { continue }
            let x = 370 + CGFloat(index) * 20
            let bar = CGRect(x: x, y: 318 - height * grow, width: 14, height: max(2, height * grow))
            s.rect(bar, radius: 2, width: 1.4)
            if index == 2 && grow >= 1 { s.hatch(Path(bar), bounds: bar, spacing: 5) }
        }

        // You pop into the corner.
        let bubble = CGRect(x: 488, y: 236, width: 118, height: 118)
        let scale = pop((t - 1.2) / 0.45)
        if scale > 0.01 {
            let outer = s.context
            s.context.translateBy(x: bubble.midX, y: bubble.midY)
            s.context.scaleBy(x: scale, y: scale)
            s.context.translateBy(x: -bubble.midX, y: -bubble.midY)
            s.context.fill(Path(ellipseIn: bubble), with: .color(s.ink.line.opacity(0.06)))
            let beforeClip = s.context
            s.context.clip(to: Path(ellipseIn: bubble.insetBy(dx: 3, dy: 3)))
            s.ellipse(CGRect(x: bubble.midX - 18, y: bubble.minY + 24, width: 36, height: 40), width: 2)
            s.stroke([CGPoint(x: bubble.midX - 58, y: bubble.maxY + 6),
                      CGPoint(x: bubble.midX - 34, y: bubble.midY + 26),
                      CGPoint(x: bubble.midX, y: bubble.midY + 20),
                      CGPoint(x: bubble.midX + 34, y: bubble.midY + 26),
                      CGPoint(x: bubble.midX + 58, y: bubble.maxY + 6)], width: 2)
            s.context = beforeClip
            s.ellipse(bubble, width: 2.6)
            s.context = outer
        }

        // Talking: waves leave the bubble towards the slide.
        if t >= 1.8 && t < 5.4 {
            for index in 0..<3 {
                let phase = ((t - 1.8) / 0.9 - Double(index) / 3).truncatingRemainder(dividingBy: 1)
                guard phase >= 0 else { continue }
                let radius = 64 + CGFloat(phase) * 26
                let center = CGPoint(x: bubble.midX, y: bubble.midY - 6)
                var wave = Path()
                wave.addArc(center: center, radius: radius, startAngle: .degrees(160), endAngle: .degrees(200),
                            clockwise: false)
                s.context.stroke(wave, with: .color(s.ink.line.opacity(1 - phase)),
                                 style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }

        // Notes in the margin, each once its thing has happened.
        if t >= 1.8 {
            s.text("you, in the corner", at: CGPoint(x: 700, y: 318), font: Hand.bold(24), anchor: .leading,
                   angle: .degrees(-4))
            s.arrow(from: CGPoint(x: 712, y: 298), to: CGPoint(x: 616, y: 282), bend: 0.3)
        }
        if t >= 0.9 {
            s.text("recording", at: CGPoint(x: 700, y: 96), font: Hand.bold(24), color: s.ink.accent,
                   anchor: .leading, angle: .degrees(3))
            s.arrow(from: CGPoint(x: 700, y: 88), to: CGPoint(x: 524, y: 72), bend: -0.18, color: s.ink.accent)
        }
    }

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
