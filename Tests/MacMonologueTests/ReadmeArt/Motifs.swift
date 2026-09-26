import SwiftUI
@testable import Mac_Monologue

/// One illustration: a name, a size, and how to draw it.
struct Motif {
    let name: String
    let size: CGSize
    let seed: UInt64
    let draw: (inout Sketcher, CGSize) -> Void
}

struct MotifView: View {
    let motif: Motif
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            var sketch = Sketcher(context, seed: motif.seed, scheme: scheme)
            motif.draw(&sketch, size)
        }
        .frame(width: motif.size.width, height: motif.size.height)
    }
}

/// Rendered on the main actor only, like any SwiftUI drawing.
@MainActor
enum ReadmeArt {
    static let all: [Motif] = [
        hero, downloadButton,
        stepMode, stepPress, stepShare,
        corners, touchCut, countdown, screens, iphoneCamera, pause, keys, subtitles, audio, mirror, privacy,
        installDownload, installDrag, installOpenAnyway, installWelcome,
    ]

    // MARK: - Hero

    /// A laptop presenting a slide, you in the corner, the red dot recording.
    static let hero = Motif(name: "hero", size: CGSize(width: 880, height: 470), seed: 7) { s, _ in
        // Laptop
        let screen = CGRect(x: 70, y: 30, width: 560, height: 360)
        s.rect(screen, radius: 18, width: 2.6)
        s.rect(screen.insetBy(dx: 14, dy: 14), radius: 6, width: 1.4)
        s.stroke([CGPoint(x: 40, y: 392), CGPoint(x: 660, y: 392),
                  CGPoint(x: 700, y: 428), CGPoint(x: 0, y: 428)], closed: true, width: 2.6)
        s.line(CGPoint(x: 300, y: 392), CGPoint(x: 400, y: 392), width: 3)

        // Menu bar, with the recording indicator on the right
        let bar = screen.minY + 44
        s.line(CGPoint(x: screen.minX + 16, y: bar), CGPoint(x: screen.maxX - 16, y: bar), width: 1.2)
        let dot = CGRect(x: 512, y: bar - 26, width: 16, height: 16)
        s.context.fill(Path(ellipseIn: dot), with: .color(s.ink.accent))
        s.text("02:14", at: CGPoint(x: 536, y: bar - 18), font: Hand.bold(18), anchor: .leading)

        // The slide
        let slide = CGRect(x: 112, y: 100, width: 330, height: 240)
        s.rect(slide, radius: 6, width: 1.8)
        s.text("Q3 plan", at: CGPoint(x: 132, y: 132), font: Hand.bold(28), anchor: .leading)
        for (index, width) in [150.0, 190.0, 120.0].enumerated() {
            let y = 178 + CGFloat(index) * 30
            s.context.fill(Path(ellipseIn: CGRect(x: 136, y: y - 3, width: 6, height: 6)), with: .color(s.ink.line))
            s.line(CGPoint(x: 152, y: y), CGPoint(x: 152 + width, y: y), width: 1.8)
        }
        // A little bar chart
        for (index, height) in [36.0, 58.0, 82.0].enumerated() {
            let x = 370 + CGFloat(index) * 20
            let bar = CGRect(x: x, y: 318 - height, width: 14, height: height)
            s.rect(bar, radius: 2, width: 1.4)
            if index == 2 { s.hatch(Path(bar), bounds: bar, spacing: 5) }
        }

        // You, in the corner
        let bubble = CGRect(x: 488, y: 236, width: 118, height: 118)
        s.context.fill(Path(ellipseIn: bubble), with: .color(s.ink.line.opacity(0.06)))
        // Head and shoulders, clipped to the circle as the real bubble is.
        let outside = s.context
        s.context.clip(to: Path(ellipseIn: bubble.insetBy(dx: 3, dy: 3)))
        s.ellipse(CGRect(x: bubble.midX - 18, y: bubble.minY + 24, width: 36, height: 40), width: 2)
        s.stroke([CGPoint(x: bubble.midX - 58, y: bubble.maxY + 6),
                  CGPoint(x: bubble.midX - 34, y: bubble.midY + 26),
                  CGPoint(x: bubble.midX, y: bubble.midY + 20),
                  CGPoint(x: bubble.midX + 34, y: bubble.midY + 26),
                  CGPoint(x: bubble.midX + 58, y: bubble.maxY + 6)], width: 2)
        s.context = outside
        s.ellipse(bubble, width: 2.6)

        // Notes in the margin
        s.text("you, in the corner", at: CGPoint(x: 700, y: 318), font: Hand.bold(24), anchor: .leading,
               angle: .degrees(-4))
        s.arrow(from: CGPoint(x: 712, y: 298), to: CGPoint(x: 616, y: 282), bend: 0.3)

        s.text("recording", at: CGPoint(x: 700, y: 96), font: Hand.bold(24), color: s.ink.accent,
               anchor: .leading, angle: .degrees(3))
        s.arrow(from: CGPoint(x: 700, y: 88), to: CGPoint(x: 524, y: 72), bend: -0.18, color: s.ink.accent)
    }

    // MARK: - Pause

    /// While recording: talk, pause, talk. In the file: one continuous take.
    static let pause = Motif(name: "pause", size: CGSize(width: 440, height: 300), seed: 21) { s, _ in
        /// Speech: bursts of louder and quieter peaks. The same `seed` draws the
        /// same wave wherever it is placed — so the file below visibly holds the
        /// very pieces recorded above.
        func talk(_ rect: CGRect, seed: UInt64) {
            s.rect(rect, radius: 7, width: 2.2)
            var shape = SeededRandom(seed)
            var points: [CGPoint] = []
            var x = rect.minX + 10
            var up = true
            var loudness = CGFloat.random(in: 0.3...1, using: &shape)
            while x < rect.maxX - 10 {
                if Int.random(in: 0..<4, using: &shape) == 0 {
                    loudness = CGFloat.random(in: 0.2...1, using: &shape)
                }
                let amplitude = max(2, loudness * CGFloat.random(in: 7...17, using: &shape))
                points.append(CGPoint(x: x, y: rect.midY + (up ? -amplitude : amplitude)))
                up.toggle()
                x += CGFloat.random(in: 5...8, using: &shape)
            }
            s.stroke(points, width: 1.5, wobble: 0.3)
        }

        let first = CGRect(x: 20, y: 50, width: 136, height: 50)
        let gap = CGRect(x: first.maxX, y: 50, width: 96, height: 50)
        let second = CGRect(x: gap.maxX, y: 50, width: 120, height: 50)

        s.text("while you record", at: CGPoint(x: 20, y: 28), font: Hand.bold(20), anchor: .leading)
        talk(first, seed: 11)
        s.rect(gap, radius: 7, color: s.ink.accent, width: 2.2)
        s.hatch(Path(roundedRect: gap, cornerRadius: 7), bounds: gap, spacing: 8, color: s.ink.accent.opacity(0.7))
        s.text("pause", at: CGPoint(x: gap.midX, y: gap.midY), font: Hand.bold(22), color: s.ink.accent)
        talk(second, seed: 12)

        for x in [gap.minX, gap.maxX] {
            s.stroke([CGPoint(x: x, y: 36), CGPoint(x: x, y: 114)], color: s.ink.accent, width: 1.6)
            s.text("✂", at: CGPoint(x: x, y: 126), font: .system(size: 18), color: s.ink.accent)
        }

        // The same two pieces, joined: the second moves left by the pause.
        let joinedFirst = CGRect(x: 20, y: 206, width: first.width, height: 50)
        let joinedSecond = CGRect(x: joinedFirst.maxX, y: 206, width: second.width, height: 50)
        s.arrow(from: CGPoint(x: second.minX + 24, y: 120), to: CGPoint(x: joinedSecond.minX + 26, y: 198), bend: -0.15)

        s.text("in the file", at: CGPoint(x: 20, y: 184), font: Hand.bold(20), anchor: .leading)
        talk(joinedFirst, seed: 11)
        talk(joinedSecond, seed: 12)
        s.text("one take,", at: CGPoint(x: joinedSecond.maxX + 18, y: 222), font: Hand.light(19), anchor: .leading)
        s.text("no dead air", at: CGPoint(x: joinedSecond.maxX + 18, y: 246), font: Hand.light(19), anchor: .leading)
    }

    // MARK: - Download button

    /// The call to action: a red pill, drawn like everything else.
    static let downloadButton = Motif(name: "download", size: CGSize(width: 380, height: 92), seed: 3) { s, _ in
        let pill = CGRect(x: 8, y: 10, width: 364, height: 70)
        s.context.fill(Path(roundedRect: pill, cornerRadius: 35), with: .color(s.ink.accent))
        s.rect(pill.insetBy(dx: -2, dy: -2), radius: 37, color: s.ink.accent, width: 2)
        // Always white: it sits on red in both schemes.
        s.text("↓  Download for Mac", at: CGPoint(x: pill.midX, y: pill.midY + 1), font: Hand.bold(30),
               color: .white)
    }

    // MARK: - Three steps

    static let stepMode = Motif(name: "step-mode", size: CGSize(width: 280, height: 200), seed: 31) { s, _ in
        let control = CGRect(x: 18, y: 22, width: 244, height: 40)
        s.rect(control, radius: 12, width: 2)
        let divider = control.minX + 86
        s.line(CGPoint(x: divider, y: control.minY + 6), CGPoint(x: divider, y: control.maxY - 6), width: 1.6)
        let chosen = CGRect(x: divider + 4, y: control.minY + 4, width: control.maxX - divider - 8, height: control.height - 8)
        s.hatch(Path(roundedRect: chosen, cornerRadius: 9), bounds: chosen, spacing: 7, color: s.ink.accent.opacity(0.55))
        s.text("Camera", at: CGPoint(x: (control.minX + divider) / 2, y: control.midY), font: Hand.bold(17))
        s.text("Screen + Camera", at: CGPoint(x: (divider + control.maxX) / 2, y: control.midY), font: Hand.bold(17))

        let screen = CGRect(x: 62, y: 86, width: 156, height: 100)
        s.rect(screen, radius: 8, width: 2)
        for (index, width) in [70.0, 96.0, 54.0].enumerated() {
            s.line(CGPoint(x: screen.minX + 16, y: screen.minY + 24 + CGFloat(index) * 18),
                   CGPoint(x: screen.minX + 16 + width, y: screen.minY + 24 + CGFloat(index) * 18), width: 1.6)
        }
        let bubble = CGRect(x: screen.maxX - 50, y: screen.maxY - 50, width: 40, height: 40)
        s.ellipse(bubble, width: 2)
        s.person(in: bubble, width: 1.4)
    }

    static let stepPress = Motif(name: "step-press", size: CGSize(width: 280, height: 200), seed: 32) { s, _ in
        let bubble = CGRect(x: 62, y: 40, width: 118, height: 118)
        s.context.fill(Path(ellipseIn: bubble), with: .color(s.ink.line.opacity(0.06)))
        s.ellipse(bubble, width: 2.4)
        s.person(in: bubble, width: 2)
        // Talking
        for (index, radius) in [16.0, 28.0, 40.0].enumerated() {
            let center = CGPoint(x: bubble.maxX + 4, y: bubble.midY - 14)
            s.stroke(stride(from: -0.55, through: 0.55, by: 0.1).map {
                CGPoint(x: center.x + cos($0) * radius, y: center.y + sin($0) * radius)
            }, width: 2 - CGFloat(index) * 0.3)
        }
        // Recording
        s.context.fill(Path(ellipseIn: CGRect(x: 92, y: 172, width: 14, height: 14)), with: .color(s.ink.accent))
        s.text("00:42", at: CGPoint(x: 114, y: 179), font: Hand.bold(18), anchor: .leading)
    }

    static let stepShare = Motif(name: "step-share", size: CGSize(width: 280, height: 200), seed: 33) { s, _ in
        // A video file…
        let file = CGRect(x: 40, y: 34, width: 96, height: 124)
        s.stroke([CGPoint(x: file.minX, y: file.minY), CGPoint(x: file.maxX - 26, y: file.minY),
                  CGPoint(x: file.maxX, y: file.minY + 26), CGPoint(x: file.maxX, y: file.maxY),
                  CGPoint(x: file.minX, y: file.maxY)], closed: true, width: 2.2)
        s.stroke([CGPoint(x: file.maxX - 26, y: file.minY), CGPoint(x: file.maxX - 26, y: file.minY + 26),
                  CGPoint(x: file.maxX, y: file.minY + 26)], width: 1.6)
        let play = [CGPoint(x: file.midX - 12, y: file.midY - 16), CGPoint(x: file.midX + 16, y: file.midY),
                    CGPoint(x: file.midX - 12, y: file.midY + 16)]
        s.context.fill(Path { $0.addLines(play); $0.closeSubpath() }, with: .color(s.ink.accent))
        s.text(".mp4", at: CGPoint(x: file.midX, y: file.maxY - 18), font: Hand.bold(16))
        // …ready to go wherever it needs to
        for (index, end) in [CGPoint(x: 240, y: 52), CGPoint(x: 252, y: 100), CGPoint(x: 240, y: 148)].enumerated() {
            s.arrow(from: CGPoint(x: 152, y: 96 + CGFloat(index - 1) * 8), to: end, bend: CGFloat(index - 1) * -0.15)
        }
    }

    // MARK: - Features

    static let corners = Motif(name: "corners", size: CGSize(width: 440, height: 300), seed: 41) { s, _ in
        let screen = CGRect(x: 30, y: 30, width: 380, height: 234)
        s.rect(screen, radius: 12, width: 2.4)
        let size: CGFloat = 70
        let spots = [
            CGRect(x: screen.minX + 18, y: screen.minY + 18, width: size, height: size),
            CGRect(x: screen.maxX - 18 - size, y: screen.minY + 18, width: size, height: size),
            CGRect(x: screen.minX + 18, y: screen.maxY - 18 - size, width: size, height: size),
        ]
        for spot in spots { s.dashedEllipse(spot, color: s.ink.soft) }
        let chosen = CGRect(x: screen.maxX - 18 - size, y: screen.maxY - 18 - size, width: size, height: size)
        s.context.fill(Path(ellipseIn: chosen), with: .color(s.ink.line.opacity(0.06)))
        s.ellipse(chosen, width: 2.4)
        s.person(in: chosen, width: 1.8)
        s.text("pick a corner", at: CGPoint(x: screen.midX, y: screen.midY - 8), font: Hand.bold(24))
        s.text("small · medium · large", at: CGPoint(x: screen.midX, y: screen.midY + 24), font: Hand.light(19),
               color: s.ink.soft)
        s.arrow(from: CGPoint(x: screen.midX + 70, y: screen.midY + 40), to: CGPoint(x: chosen.minX - 6, y: chosen.midY),
                bend: 0.25, color: s.ink.accent)
    }

    /// Finger on the trackpad: the screen, you in the corner. Let go: you, full frame.
    static let touchCut = Motif(name: "touch-cut", size: CGSize(width: 440, height: 300), seed: 49) { s, _ in
        func trackpad(below screen: CGRect, touched: Bool) -> CGRect {
            let pad = CGRect(x: screen.midX - 46, y: screen.maxY + 26, width: 92, height: 60)
            s.rect(pad, radius: 9, width: 2)
            if touched {
                let finger = CGRect(x: pad.midX - 9, y: pad.midY - 9, width: 18, height: 18)
                s.context.fill(Path(ellipseIn: finger), with: .color(s.ink.accent))
                s.dashedEllipse(finger.insetBy(dx: -8, dy: -8), color: s.ink.accent)
            }
            return pad
        }

        // Finger down: the slide, with you in the bubble.
        let slide = CGRect(x: 20, y: 36, width: 170, height: 112)
        s.rect(slide, radius: 10, width: 2.4)
        for (index, width) in [74.0, 96.0, 52.0].enumerated() {
            let y = slide.minY + 26 + CGFloat(index) * 20
            s.line(CGPoint(x: slide.minX + 16, y: y), CGPoint(x: slide.minX + 16 + width, y: y), width: 1.6)
        }
        let bubble = CGRect(x: slide.maxX - 50, y: slide.maxY - 50, width: 40, height: 40)
        s.context.fill(Path(ellipseIn: bubble), with: .color(s.ink.line.opacity(0.06)))
        s.ellipse(bubble, width: 2)
        s.person(in: bubble, width: 1.4)
        let down = trackpad(below: slide, touched: true)
        s.text("finger down", at: CGPoint(x: down.midX, y: down.maxY + 20), font: Hand.bold(20))

        // Let go: you, filling the picture.
        let head = CGRect(x: 250, y: 36, width: 170, height: 112)
        s.context.fill(Path(roundedRect: head, cornerRadius: 10), with: .color(s.ink.line.opacity(0.06)))
        let outside = s.context
        s.context.clip(to: Path(roundedRect: head.insetBy(dx: 3, dy: 3), cornerRadius: 8))
        s.ellipse(CGRect(x: head.midX - 20, y: head.minY + 18, width: 40, height: 46), width: 2)
        s.stroke([CGPoint(x: head.midX - 76, y: head.maxY + 8), CGPoint(x: head.midX - 44, y: head.minY + 82),
                  CGPoint(x: head.midX, y: head.minY + 74), CGPoint(x: head.midX + 44, y: head.minY + 82),
                  CGPoint(x: head.midX + 76, y: head.maxY + 8)], width: 2)
        s.context = outside
        s.rect(head, radius: 10, width: 2.4)
        let up = trackpad(below: head, touched: false)
        s.text("let go", at: CGPoint(x: up.midX, y: up.maxY + 20), font: Hand.bold(20))

        // The cut between them.
        s.arrow(from: CGPoint(x: slide.maxX + 8, y: slide.midY + 6), to: CGPoint(x: head.minX - 8, y: head.midY + 6),
                bend: -0.3, color: s.ink.accent)
        s.text("✂", at: CGPoint(x: (slide.maxX + head.minX) / 2, y: slide.midY - 24), font: .system(size: 20),
               color: s.ink.accent)
    }

    /// 3 - 2 - 1 on the screen, out of the video; the finger chooses the opening.
    static let countdown = Motif(name: "countdown", size: CGSize(width: 440, height: 300), seed: 50) { s, _ in
        let screen = CGRect(x: 30, y: 20, width: 290, height: 186)
        s.rect(screen, radius: 12, width: 2.4)
        let circle = CGRect(x: screen.midX - 58, y: screen.minY + 22, width: 116, height: 116)
        s.context.fill(Path(ellipseIn: circle), with: .color(s.ink.line.opacity(0.06)))
        s.ellipse(circle, width: 2.4)
        s.text("3", at: CGPoint(x: circle.midX, y: circle.midY + 2), font: Hand.bold(72))
        s.text("2 · 1", at: CGPoint(x: screen.midX, y: circle.maxY + 24), font: Hand.light(20), color: s.ink.soft)

        s.text("never in", at: CGPoint(x: 336, y: 52), font: Hand.bold(20), color: s.ink.accent, anchor: .leading,
               angle: .degrees(3))
        s.text("the video", at: CGPoint(x: 336, y: 76), font: Hand.bold(20), color: s.ink.accent, anchor: .leading,
               angle: .degrees(3))
        s.arrow(from: CGPoint(x: 340, y: 94), to: CGPoint(x: circle.maxX + 8, y: circle.midY - 6), bend: 0.3,
                color: s.ink.accent)

        let pad = CGRect(x: screen.midX - 50, y: screen.maxY + 24, width: 100, height: 58)
        s.rect(pad, radius: 9, width: 2)
        let finger = CGRect(x: pad.midX - 9, y: pad.midY - 9, width: 18, height: 18)
        s.context.fill(Path(ellipseIn: finger), with: .color(s.ink.accent))
        s.dashedEllipse(finger.insetBy(dx: -8, dy: -8), color: s.ink.accent)
        s.text("finger down:", at: CGPoint(x: pad.maxX + 20, y: pad.midY - 12), font: Hand.bold(18), anchor: .leading)
        s.text("starts on the screen", at: CGPoint(x: pad.maxX + 20, y: pad.midY + 12), font: Hand.light(18),
               anchor: .leading)
    }

    static let keys = Motif(name: "keys", size: CGSize(width: 440, height: 250), seed: 42) { s, _ in
        s.context.translateBy(x: 40, y: 10)
        drawKeys(&s, shortcut: .defaultToggle)
    }

    /// The keys and the hand from the welcome steps — the same layout as
    /// `KeyCapView`, drawn with the pen.
    static func drawKeys(_ s: inout Sketcher, shortcut: Shortcut) {
        let layout = KeyCapView.Layout(shortcut: shortcut)
        for key in layout.keys {
            if key.isPressed {
                s.context.fill(Path(roundedRect: key.rect, cornerRadius: 6), with: .color(s.ink.accent.opacity(0.14)))
                s.rect(key.rect, radius: 6, color: s.ink.accent, width: 2.2)
            } else {
                s.rect(key.rect, radius: 6, color: key.isFaint ? s.ink.soft : s.ink.line, width: 1.6)
            }
            guard !key.symbol.isEmpty else { continue }
            if key.name.isEmpty {
                s.text(key.symbol, at: CGPoint(x: key.rect.midX, y: key.rect.midY), font: Hand.bold(22))
            } else {
                s.text(key.symbol, at: CGPoint(x: key.rect.maxX - 11, y: key.rect.minY + 11), font: .system(size: 12),
                       color: key.isFaint ? s.ink.soft : s.ink.line)
                s.text(key.name, at: CGPoint(x: key.rect.midX, y: key.rect.maxY - 10), font: Hand.light(12),
                       color: key.isFaint ? s.ink.soft : s.ink.line)
            }
        }
        // The hand: opaque in its own layer, made translucent as a whole.
        var hands = s.context
        hands.opacity = s.ink.handOpacity
        let ink = s.ink.line
        hands.drawLayer { layer in
            for hand in layout.hands {
                layer.fill(Path(ellipseIn: CGRect(x: hand.palm.x - 82, y: hand.palm.y - 62, width: 164, height: 124)),
                           with: .color(ink))
                for tip in hand.fingertips {
                    let dx = tip.x - hand.palm.x, dy = tip.y - hand.palm.y
                    let length = max(1, hypot(dx, dy))
                    var finger = Path()
                    finger.move(to: CGPoint(x: hand.palm.x + dx / length * 48, y: hand.palm.y + dy / length * 48))
                    finger.addLine(to: CGPoint(x: tip.x, y: tip.y + 6))
                    layer.stroke(finger, with: .color(ink), style: StrokeStyle(lineWidth: 24, lineCap: .round))
                }
                if let thumb = hand.thumb {
                    var path = Path()
                    path.move(to: CGPoint(x: hand.palm.x + 64, y: hand.palm.y - 34))
                    path.addLine(to: CGPoint(x: thumb.x, y: thumb.y + 6))
                    layer.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 27, lineCap: .round))
                }
            }
        }
    }

    static let audio = Motif(name: "audio", size: CGSize(width: 440, height: 280), seed: 43) { s, _ in
        // A microphone
        let head = CGRect(x: 62, y: 34, width: 34, height: 52)
        s.rect(head, radius: 17, width: 2.2)
        s.stroke([CGPoint(x: 54, y: 70), CGPoint(x: 56, y: 92), CGPoint(x: 79, y: 102),
                  CGPoint(x: 102, y: 92), CGPoint(x: 104, y: 70)], width: 1.8)
        s.line(CGPoint(x: 79, y: 102), CGPoint(x: 79, y: 120), width: 1.8)
        s.text("your voice", at: CGPoint(x: 79, y: 140), font: Hand.bold(18))

        // Music, or a video playing on screen
        s.text("♫", at: CGPoint(x: 80, y: 206), font: .system(size: 44), color: s.ink.line)
        s.text("your Mac", at: CGPoint(x: 79, y: 250), font: Hand.bold(18))

        // Both into one track
        s.arrow(from: CGPoint(x: 130, y: 80), to: CGPoint(x: 236, y: 138), bend: -0.2)
        s.arrow(from: CGPoint(x: 130, y: 212), to: CGPoint(x: 236, y: 156), bend: 0.2)
        let track = CGRect(x: 246, y: 116, width: 170, height: 58)
        s.rect(track, radius: 8, width: 2.4)
        var shape = SeededRandom(99)
        var points: [CGPoint] = []
        var x = track.minX + 12
        var up = true
        while x < track.maxX - 12 {
            let amplitude = CGFloat.random(in: 5...19, using: &shape)
            points.append(CGPoint(x: x, y: track.midY + (up ? -amplitude : amplitude)))
            up.toggle()
            x += 7
        }
        s.stroke(points, color: s.ink.accent, width: 1.6, wobble: 0.4)
        s.text("one track", at: CGPoint(x: track.midX, y: track.maxY + 26), font: Hand.bold(20))
    }

    /// Two screens: the laptop stays out of it, the second screen is recorded.
    static let screens = Motif(name: "screens", size: CGSize(width: 440, height: 300), seed: 46) { s, _ in
        s.text("pick a screen", at: CGPoint(x: 220, y: 28), font: Hand.bold(24))

        // The laptop, not recorded
        let laptop = CGRect(x: 34, y: 112, width: 150, height: 96)
        s.rect(laptop, radius: 8, color: s.ink.soft, width: 2)
        s.stroke([CGPoint(x: 24, y: 210), CGPoint(x: 194, y: 210), CGPoint(x: 204, y: 224), CGPoint(x: 14, y: 224)],
                 closed: true, color: s.ink.soft, width: 2)
        for (y, length) in [(136.0, 90.0), (152.0, 70.0), (168.0, 80.0)] {
            s.line(CGPoint(x: 52, y: y), CGPoint(x: 52 + length, y: y), color: s.ink.soft, width: 1.4)
        }
        s.text("built-in", at: CGPoint(x: 109, y: 252), font: Hand.light(19), color: s.ink.soft)

        // The second screen, recorded: slide, bubble, red dot
        let display = CGRect(x: 226, y: 66, width: 190, height: 126)
        s.rect(display, radius: 8, width: 2.4)
        s.line(CGPoint(x: 321, y: 192), CGPoint(x: 321, y: 212), width: 2.4)
        s.line(CGPoint(x: 290, y: 214), CGPoint(x: 352, y: 214), width: 2.4)
        for (y, length) in [(96.0, 90.0), (112.0, 110.0), (128.0, 70.0)] {
            s.line(CGPoint(x: 246, y: y), CGPoint(x: 246 + length, y: y), width: 1.6)
        }
        let bubble = CGRect(x: 356, y: 134, width: 52, height: 52)
        s.context.fill(Path(ellipseIn: bubble), with: .color(s.ink.line.opacity(0.06)))
        s.ellipse(bubble, width: 2)
        s.person(in: bubble, width: 1.7)
        s.context.fill(Path(ellipseIn: CGRect(x: 398, y: 74, width: 9, height: 9)), with: .color(s.ink.accent))
        s.text("second screen", at: CGPoint(x: 321, y: 244), font: Hand.bold(20))
        s.check(at: CGPoint(x: 268, y: 272), size: 16, color: s.ink.accent)
        s.text("gets recorded", at: CGPoint(x: 330, y: 272), font: Hand.light(19), color: s.ink.accent)
    }

    /// An iPhone clipped to the top of a Mac, standing in for its camera.
    static let iphoneCamera = Motif(name: "iphone-camera", size: CGSize(width: 440, height: 300), seed: 47) { s, _ in
        // The Mac
        let screen = CGRect(x: 40, y: 110, width: 250, height: 150)
        s.rect(screen, radius: 10, width: 2.4)
        s.stroke([CGPoint(x: 24, y: 262), CGPoint(x: 306, y: 262), CGPoint(x: 322, y: 280), CGPoint(x: 8, y: 280)],
                 closed: true, width: 2.4)
        for (y, length) in [(146.0, 110.0), (164.0, 140.0), (182.0, 90.0)] {
            s.line(CGPoint(x: 62, y: y), CGPoint(x: 62 + length, y: y), color: s.ink.soft, width: 1.4)
        }
        // You, sharp, in the corner of what is recorded
        let bubble = CGRect(x: 214, y: 186, width: 62, height: 62)
        s.context.fill(Path(ellipseIn: bubble), with: .color(s.ink.line.opacity(0.06)))
        s.ellipse(bubble, width: 2)
        s.person(in: bubble, width: 1.8)

        // The iPhone, its back to us, on a clip over the top edge
        let phone = CGRect(x: 138, y: 22, width: 54, height: 100)
        s.rect(CGRect(x: 150, y: 104, width: 30, height: 14), radius: 3, width: 2)
        s.context.fill(Path(roundedRect: phone, cornerRadius: 11), with: .color(s.ink.line.opacity(0.05)))
        s.rect(phone, radius: 11, width: 2.4)
        let lenses = CGRect(x: phone.minX + 7, y: phone.minY + 7, width: 26, height: 26)
        s.rect(lenses, radius: 6, width: 1.6)
        s.ellipse(CGRect(x: lenses.minX + 3, y: lenses.minY + 3, width: 9, height: 9), width: 1.4)
        s.ellipse(CGRect(x: lenses.minX + 13, y: lenses.minY + 13, width: 9, height: 9), width: 1.4)

        // No cable: the waves of a wireless link, off to the left
        for radius in [14.0, 26.0] {
            let points = stride(from: .pi - 0.7, through: .pi + 0.7, by: 0.1).map { angle in
                CGPoint(x: phone.minX - 6 + cos(angle) * radius, y: phone.midY + sin(angle) * radius)
            }
            s.stroke(points, color: s.ink.soft, width: 1.8, wobble: 0.4)
        }

        s.text("your iPhone", at: CGPoint(x: 290, y: 48), font: Hand.bold(24), anchor: .leading)
        s.text("as the camera", at: CGPoint(x: 290, y: 78), font: Hand.light(20), color: s.ink.accent, anchor: .leading)
        s.arrow(from: CGPoint(x: 284, y: 58), to: CGPoint(x: 200, y: 54), bend: 0.2)
        s.text("no cable", at: CGPoint(x: 62, y: 70), font: Hand.light(19), color: s.ink.soft)
        s.text("keeps you", at: CGPoint(x: 322, y: 196), font: Hand.light(19), color: s.ink.soft, anchor: .leading)
        s.text("in frame", at: CGPoint(x: 322, y: 220), font: Hand.light(19), color: s.ink.soft, anchor: .leading)
        s.arrow(from: CGPoint(x: 318, y: 214), to: CGPoint(x: 282, y: 218), bend: 0.3, color: s.ink.soft)
    }

    /// Speech in the take, subtitles in four languages out, all on the Mac.
    static let subtitles = Motif(name: "subtitles", size: CGSize(width: 440, height: 280), seed: 48) { s, _ in
        // The video, with a subtitle along the bottom
        let frame = CGRect(x: 24, y: 34, width: 250, height: 170)
        s.rect(frame, radius: 10, width: 2.4)
        let bubble = CGRect(x: frame.midX - 44, y: frame.minY + 16, width: 88, height: 88)
        s.person(in: bubble, width: 2)
        let bar = CGRect(x: frame.minX + 26, y: frame.maxY - 50, width: frame.width - 52, height: 32)
        s.context.fill(Path(roundedRect: bar, cornerRadius: 5), with: .color(s.ink.line.opacity(0.1)))
        s.text("Hello and welcome!", at: CGPoint(x: bar.midX, y: bar.midY), font: Hand.bold(18))

        // The languages to switch between
        let codes = [("DE", true), ("EN", true), ("FR", false), ("ES", true)]
        for (index, (code, chosen)) in codes.enumerated() {
            let pill = CGRect(x: 318, y: 30 + CGFloat(index) * 44, width: 64, height: 32)
            s.rect(pill, radius: 16, color: chosen ? s.ink.line : s.ink.soft, width: chosen ? 2.2 : 1.6)
            s.text(code, at: CGPoint(x: pill.midX - 6, y: pill.midY), font: Hand.bold(18),
                   color: chosen ? s.ink.line : s.ink.soft)
            if chosen { s.check(at: CGPoint(x: pill.maxX + 18, y: pill.midY), size: 14) }
        }

        s.text("made on your Mac", at: CGPoint(x: frame.midX, y: 236), font: Hand.bold(20))
        s.text("nothing uploaded", at: CGPoint(x: frame.midX, y: 262), font: Hand.light(18), color: s.ink.soft)
    }

    static let mirror = Motif(name: "mirror", size: CGSize(width: 440, height: 280), seed: 44) { s, _ in
        func frame(_ rect: CGRect, title: String, mirrored: Bool) {
            s.rect(rect, radius: 10, width: 2.2)
            let bubble = CGRect(x: rect.midX - 42, y: rect.minY + 20, width: 84, height: 84)
            s.person(in: bubble, width: 1.8)
            let sign = CGRect(x: rect.midX - 58, y: rect.minY + 102, width: 116, height: 44)
            s.rect(sign, radius: 4, width: 2)
            s.text("HELLO", at: CGPoint(x: sign.midX, y: sign.midY + 1), font: Hand.bold(24),
                   color: mirrored ? s.ink.soft : s.ink.line, mirrored: mirrored)
            s.text(title, at: CGPoint(x: rect.midX, y: rect.maxY + 22), font: Hand.bold(18))
        }
        frame(CGRect(x: 30, y: 30, width: 170, height: 170), title: "preview", mirrored: true)
        frame(CGRect(x: 240, y: 30, width: 170, height: 170), title: "your file", mirrored: false)
        s.text("like a mirror", at: CGPoint(x: 115, y: 250), font: Hand.light(17), color: s.ink.soft)
        s.text("reads right", at: CGPoint(x: 325, y: 250), font: Hand.light(17), color: s.ink.accent)
    }

    static let privacy = Motif(name: "privacy", size: CGSize(width: 440, height: 280), seed: 45) { s, _ in
        // The Mac, with a padlock
        let screen = CGRect(x: 40, y: 50, width: 190, height: 124)
        s.rect(screen, radius: 10, width: 2.4)
        s.stroke([CGPoint(x: 26, y: 176), CGPoint(x: 244, y: 176), CGPoint(x: 258, y: 194), CGPoint(x: 12, y: 194)],
                 closed: true, width: 2.4)
        let lock = CGRect(x: screen.midX - 22, y: screen.midY - 6, width: 44, height: 34)
        s.rect(lock, radius: 5, color: s.ink.accent, width: 2.2)
        s.stroke(stride(from: CGFloat.pi, through: 2 * .pi, by: .pi / 10).map {
            CGPoint(x: lock.midX + cos($0) * 14, y: lock.minY + sin($0) * 18)
        }, color: s.ink.accent, width: 2.2)

        // A cloud, crossed out
        let cloud = [CGPoint(x: 300, y: 120), CGPoint(x: 296, y: 96), CGPoint(x: 318, y: 82), CGPoint(x: 340, y: 64),
                     CGPoint(x: 372, y: 66), CGPoint(x: 390, y: 86), CGPoint(x: 414, y: 92), CGPoint(x: 416, y: 118)]
        s.stroke(cloud, closed: true, color: s.ink.soft, width: 2)
        s.line(CGPoint(x: 296, y: 140), CGPoint(x: 420, y: 52), color: s.ink.accent, width: 2.6)
        s.text("no cloud,", at: CGPoint(x: 356, y: 176), font: Hand.bold(20))
        s.text("no account", at: CGPoint(x: 356, y: 202), font: Hand.bold(20))
        s.text("stays on your Mac", at: CGPoint(x: 135, y: 236), font: Hand.bold(20))
    }

    // MARK: - Install

    static let installDownload = Motif(name: "install-1", size: CGSize(width: 220, height: 170), seed: 51) { s, _ in
        s.arrow(from: CGPoint(x: 110, y: 18), to: CGPoint(x: 110, y: 72), bend: 0, color: s.ink.accent)
        let zip = CGRect(x: 66, y: 80, width: 88, height: 70)
        s.rect(zip, radius: 6, width: 2.2)
        for index in 0..<5 {
            let y = zip.minY + 8 + CGFloat(index) * 8
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            s.line(CGPoint(x: zip.midX, y: y), CGPoint(x: zip.midX + side * 7, y: y), width: 1.6)
        }
        s.text(".zip", at: CGPoint(x: zip.midX, y: zip.maxY - 12), font: Hand.bold(15))
    }

    static let installDrag = Motif(name: "install-2", size: CGSize(width: 220, height: 170), seed: 52) { s, _ in
        let icon = CGRect(x: 18, y: 50, width: 60, height: 60)
        s.rect(icon, radius: 14, width: 2.2)
        s.context.fill(Path(ellipseIn: CGRect(x: icon.midX - 11, y: icon.midY - 11, width: 22, height: 22)),
                       with: .color(s.ink.accent))
        s.arrow(from: CGPoint(x: 86, y: 80), to: CGPoint(x: 132, y: 80), bend: -0.3)
        let folder = [CGPoint(x: 140, y: 58), CGPoint(x: 164, y: 58), CGPoint(x: 172, y: 66),
                      CGPoint(x: 204, y: 66), CGPoint(x: 204, y: 112), CGPoint(x: 140, y: 112)]
        s.stroke(folder, closed: true, width: 2.2)
        s.text("A", at: CGPoint(x: 172, y: 90), font: Hand.bold(22), color: s.ink.soft)
        s.text("Applications", at: CGPoint(x: 172, y: 134), font: Hand.bold(15))
    }

    static let installOpenAnyway = Motif(name: "install-3", size: CGSize(width: 220, height: 170), seed: 53) { s, _ in
        s.text("Privacy & Security", at: CGPoint(x: 110, y: 34), font: Hand.light(15), color: s.ink.soft)
        let button = CGRect(x: 44, y: 60, width: 132, height: 38)
        s.rect(button, radius: 8, width: 2.2)
        s.text("Open Anyway", at: CGPoint(x: button.midX, y: button.midY), font: Hand.bold(18))
        // The pointer, clicking it
        let tip = CGPoint(x: 168, y: 92)
        s.stroke([tip, CGPoint(x: tip.x, y: tip.y + 34), CGPoint(x: tip.x + 9, y: tip.y + 26),
                  CGPoint(x: tip.x + 16, y: tip.y + 40), CGPoint(x: tip.x + 22, y: tip.y + 37),
                  CGPoint(x: tip.x + 15, y: tip.y + 23), CGPoint(x: tip.x + 26, y: tip.y + 23)],
                 closed: true, color: s.ink.accent, width: 2)
        s.text("once", at: CGPoint(x: 70, y: 132), font: Hand.bold(18), color: s.ink.accent)
    }

    static let installWelcome = Motif(name: "install-4", size: CGSize(width: 220, height: 170), seed: 54) { s, _ in
        let window = CGRect(x: 30, y: 20, width: 160, height: 130)
        s.rect(window, radius: 10, width: 2.2)
        s.line(CGPoint(x: window.minX + 8, y: window.minY + 22), CGPoint(x: window.maxX - 8, y: window.minY + 22),
               width: 1.2)
        for (index, label) in ["Camera", "Microphone", "Screen"].enumerated() {
            let y = window.minY + 48 + CGFloat(index) * 30
            s.text(label, at: CGPoint(x: window.minX + 18, y: y), font: Hand.bold(16), anchor: .leading)
            s.check(at: CGPoint(x: window.maxX - 26, y: y))
        }
    }
}
