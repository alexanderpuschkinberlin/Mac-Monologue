import SwiftUI

/// A drawing of the keys in a shortcut, with a translucent hand whose fingers
/// rest on exactly those keys.
///
/// For someone who has never read "⌃⌥⌘R", the symbols mean nothing; a picture of
/// where the fingers go needs no explanation. The hand is deliberately abstract —
/// a round palm and capsule fingers — because a drawn attempt at a realistic hand
/// would look wrong, and one that does not try cannot.
struct KeyCapView: View {
    let shortcut: Shortcut

    static let size = CGSize(width: 360, height: 190)

    var body: some View {
        Canvas { context, _ in
            let layout = Layout(shortcut: shortcut)

            for key in layout.keys {
                draw(key, in: &context)
            }

            // The whole hand is drawn opaque into one layer, and only the finished
            // layer is made translucent — so where palm and fingers overlap, they
            // do not darken each other.
            var hands = context
            hands.opacity = 0.22
            hands.drawLayer { layer in
                for hand in layout.hands {
                    drawHand(hand, in: &layer)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .accessibilityElement()
        .accessibilityLabel(Self.spokenDescription(of: shortcut))
    }

    private func draw(_ key: Key, in context: inout GraphicsContext) {
        let shape = Path(roundedRect: key.rect, cornerRadius: 6)
        if key.isPressed {
            context.fill(shape, with: .color(.accentColor.opacity(0.28)))
            context.stroke(shape, with: .color(.accentColor), lineWidth: 1.5)
        } else {
            context.fill(shape, with: .color(Color(nsColor: .controlBackgroundColor).opacity(key.isFaint ? 0.5 : 1)))
            context.stroke(shape, with: .color(.secondary.opacity(key.isFaint ? 0.25 : 0.55)), lineWidth: 1)
        }

        guard !key.symbol.isEmpty else { return }
        let ink: Color = key.isPressed ? .primary : .secondary
        if key.name.isEmpty {
            context.draw(Text(key.symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(ink),
                         at: CGPoint(x: key.rect.midX, y: key.rect.midY))
        } else {
            // Like the real keys: symbol at the top, name underneath.
            context.draw(Text(key.symbol).font(.system(size: 12)).foregroundStyle(ink),
                         at: CGPoint(x: key.rect.maxX - 11, y: key.rect.minY + 11))
            context.draw(Text(key.name).font(.system(size: 9)).foregroundStyle(ink),
                         at: CGPoint(x: key.rect.midX, y: key.rect.maxY - 9))
        }
    }

    private func drawHand(_ hand: Hand, in context: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(.primary)
        context.fill(Path(ellipseIn: CGRect(x: hand.palm.x - 82, y: hand.palm.y - 62, width: 164, height: 124)),
                     with: ink)
        for tip in hand.fingertips {
            // Each finger grows from the edge of the palm, in the direction of its
            // key — fanned out like a real hand, not radiating from one point —
            // and ends just below the key's middle, leaving its label readable.
            let dx = tip.x - hand.palm.x
            let dy = tip.y - hand.palm.y
            let length = max(1, hypot(dx, dy))
            let knuckle = CGPoint(x: hand.palm.x + dx / length * 48, y: hand.palm.y + dy / length * 48)
            var finger = Path()
            finger.move(to: knuckle)
            finger.addLine(to: CGPoint(x: tip.x, y: tip.y + 6))
            context.stroke(finger, with: ink, style: StrokeStyle(lineWidth: 24, lineCap: .round))
        }
        if let thumb = hand.thumb {
            // The thumb comes out of the side of the palm, not its top — which is
            // also what keeps it apart from the finger reaching past it.
            var path = Path()
            path.move(to: CGPoint(x: hand.palm.x + 64, y: hand.palm.y - 34))
            path.addLine(to: CGPoint(x: thumb.x, y: thumb.y + 6))
            context.stroke(path, with: ink, style: StrokeStyle(lineWidth: 27, lineCap: .round))
        }
    }

    static func spokenDescription(of shortcut: Shortcut) -> String {
        var held: [String] = []
        if shortcut.hasControl { held.append("Control") }
        if shortcut.hasOption { held.append("Option") }
        if shortcut.hasShift { held.append("Shift") }
        if shortcut.hasCommand { held.append("Command") }
        let key = shortcut.keyLabel == "↩" ? "Return" : shortcut.keyLabel
        return "Hold \(ListFormatter.localizedString(byJoining: held)), then press \(key)"
    }

    // MARK: - Geometry

    struct Key {
        var rect: CGRect
        var symbol: String
        var name: String = ""
        var isPressed = false
        var isFaint = false
    }

    struct Hand {
        var palm: CGPoint
        var fingertips: [CGPoint]
        var thumb: CGPoint?
    }

    /// Where each key sits, and which hand presses what — a small slice of a Mac
    /// keyboard's lower left, with the target key where it really is relative to it.
    struct Layout {
        var keys: [Key] = []
        var hands: [Hand] = []

        /// Keys a left hand reaches while holding the modifiers.
        private static let leftHandLetters = Set("QWERTASDFGZXCVB".map(String.init))

        init(shortcut: Shortcut) {
            let bottom: CGFloat = 94, upper: CGFloat = 50, height: CGFloat = 38

            let control = CGRect(x: 18, y: bottom, width: 50, height: height)
            let option = CGRect(x: 74, y: bottom, width: 50, height: height)
            let command = CGRect(x: 130, y: bottom, width: 62, height: height)
            let shift = CGRect(x: 18, y: upper, width: 74, height: height)

            keys.append(Key(rect: control, symbol: "⌃", name: "control", isPressed: shortcut.hasControl))
            keys.append(Key(rect: option, symbol: "⌥", name: "option", isPressed: shortcut.hasOption))
            keys.append(Key(rect: command, symbol: "⌘", name: "command", isPressed: shortcut.hasCommand))
            keys.append(Key(rect: shift, symbol: "⇧", name: "shift", isPressed: shortcut.hasShift,
                            isFaint: !shortcut.hasShift))
            keys.append(Key(rect: CGRect(x: 198, y: bottom, width: 86, height: height), symbol: "", isFaint: true))

            var leftTips: [CGPoint] = []
            if shortcut.hasControl { leftTips.append(control.center) }
            if shortcut.hasOption { leftTips.append(option.center) }
            if shortcut.hasShift { leftTips.append(shift.center) }
            // Command is held with the thumb.
            let thumb = shortcut.hasCommand ? command.center : nil

            let target: CGRect
            if shortcut.keyLabel == "↩" {
                target = CGRect(x: 292, y: upper, width: 52, height: bottom - upper + height)
                keys.append(Key(rect: target, symbol: "↩", name: "return", isPressed: true))
            } else {
                // Up and to the right of command, where the letter keys really are.
                target = CGRect(x: 206, y: upper, width: 38, height: height)
                keys.append(Key(rect: CGRect(x: 162, y: upper, width: 38, height: height), symbol: "", isFaint: true))
                keys.append(Key(rect: CGRect(x: 250, y: upper, width: 38, height: height), symbol: "", isFaint: true))
                keys.append(Key(rect: target, symbol: shortcut.keyLabel, isPressed: true))
            }

            if shortcut.keyLabel != "↩", Self.leftHandLetters.contains(shortcut.keyLabel) {
                leftTips.append(target.center)
            } else {
                // Too far for the hand already holding the modifiers.
                hands.append(Hand(palm: CGPoint(x: target.midX + 30, y: 212), fingertips: [target.center]))
            }

            if !leftTips.isEmpty || thumb != nil {
                let xs = leftTips.map(\.x) + (thumb.map { [$0.x - 40] } ?? [])
                let averageX = xs.reduce(0, +) / CGFloat(xs.count)
                hands.insert(Hand(palm: CGPoint(x: averageX, y: 212), fingertips: leftTips, thumb: thumb), at: 0)
            }
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
