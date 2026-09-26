import SwiftUI

/// One fader between your voice and the Mac's sound, like a DJ's between two
/// decks: in the middle both play full — the sound every take had before — and
/// towards either end the other side fades out. Each side has its meter, showing
/// what goes into the recording after the fader. Live during a take.
struct AudioCrossfaderView: View {
    @Binding var balance: Float
    @Binding var ducksSystemAudio: Bool
    let hasMicrophone: Bool
    let voiceLevel: Float
    let voicePeak: Float
    let voiceClipping: Bool
    let systemLevel: Float
    let systemPeak: Float

    var body: some View {
        let gains = AudioMix.gains(balance: balance)
        HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 3) {
                HStack {
                    Label("Voice", systemImage: "mic.fill")
                    Spacer()
                    Text(positionLabel)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Label("Mac sound", systemImage: "speaker.wave.2.fill")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    meter(level: voiceLevel, peak: voicePeak, clipping: voiceClipping, gain: gains.voice,
                          help: "Your voice as it goes into the recording")
                        .opacity(hasMicrophone ? 1 : 0.35)
                    DJFader(value: $balance)
                        .help("Towards Voice, the Mac gets quieter; towards Mac sound, your voice does. "
                              + "Double-click for both full.")
                    meter(level: systemLevel, peak: systemPeak, clipping: false, gain: gains.system,
                          help: "The Mac's sound as it goes into the recording")
                }
            }
            .frame(width: 330)

            Toggle(isOn: $ducksSystemAudio) {
                Image(systemName: ducksSystemAudio ? "speaker.wave.1.fill" : "speaker.wave.1")
            }
            .toggleStyle(.button)
            .help("Lower Mac sound while I talk")
            .accessibilityLabel("Lower Mac sound while I talk")
        }
    }

    private var positionLabel: String {
        switch balance {
        case -0.02...0.02: "both full"
        case ...(-0.98): "Mac sound off"
        case 0.98...: "voice off"
        default: ""
        }
    }

    private func meter(level: Float, peak: Float, clipping: Bool, gain: Float, help: String) -> some View {
        let shift = AudioMix.decibels(gain)
        return LevelMeterView(level: max(AudioLevelMeter.floorDB, level + shift),
                              peak: max(AudioLevelMeter.floorDB, peak + shift),
                              isClipping: clipping, compact: true, help: help)
            .frame(width: 80)
    }
}

/// A crossfader drawn like the one on a DJ mixer: a flat cap with grip lines
/// on a rail, a scale underneath with a long mark at the centre, and the colour
/// filling from the centre towards the cap — this is a balance, not a volume.
/// The centre catches the cap, with a tick on the trackpad.
struct DJFader: View {
    @Binding var value: Float
    @State private var isCentred = true
    @FocusState private var isFocused: Bool

    static let size = CGSize(width: 150, height: 30)
    static let cap = CGSize(width: 12, height: 22)
    private static let railY: CGFloat = 11

    var body: some View {
        Canvas { context, size in
            let travel = size.width - Self.cap.width
            let centreX = size.width / 2
            let capX = Self.cap.width / 2 + CGFloat((value + 1) / 2) * travel

            // Rail, and the fill from the centre to the cap.
            let rail = CGRect(x: Self.cap.width / 2, y: Self.railY - 2, width: travel, height: 4)
            context.fill(Path(roundedRect: rail, cornerRadius: 2), with: .color(.primary.opacity(0.15)))
            let fill = CGRect(x: min(centreX, capX), y: rail.minY, width: abs(capX - centreX), height: rail.height)
            context.fill(Path(roundedRect: fill, cornerRadius: 2), with: .color(.accentColor))

            // Scale: nine marks, the centre long and strong.
            for index in 0..<9 {
                let x = Self.cap.width / 2 + travel * CGFloat(index) / 8
                let centre = index == 4
                let mark = CGRect(x: x - (centre ? 1 : 0.5), y: Self.cap.height + 1,
                                  width: centre ? 2 : 1, height: centre ? 7 : 4)
                context.fill(Path(mark), with: .color(centre ? .primary : .secondary))
            }

            // The cap, with three grip lines; the middle one lights up at the centre.
            let cap = CGRect(x: capX - Self.cap.width / 2, y: 0, width: Self.cap.width, height: Self.cap.height)
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.25), radius: 1.5, y: 1))
            // Opaque underneath: the control colour alone lets the rail show through in dark mode.
            shadowed.fill(Path(roundedRect: cap, cornerRadius: 3), with: .color(Color(nsColor: .windowBackgroundColor)))
            context.fill(Path(roundedRect: cap, cornerRadius: 3), with: .color(Color(nsColor: .controlColor)))
            context.stroke(Path(roundedRect: cap.insetBy(dx: 0.25, dy: 0.25), cornerRadius: 3),
                           with: .color(.primary.opacity(isFocused ? 0.6 : 0.3)), lineWidth: isFocused ? 1 : 0.5)
            for (index, dy) in [-4.0, 0.0, 4.0].enumerated() {
                let line = CGRect(x: cap.minX + 3, y: cap.midY + dy - 0.5, width: cap.width - 6, height: 1)
                let lit = index == 1 && value == 0
                context.fill(Path(line), with: .color(lit ? .accentColor : .primary.opacity(0.45)))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            set(FaderMath.value(forX: drag.location.x, width: Self.size.width, capWidth: Self.cap.width))
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded { set(0) })
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) { set(FaderMath.step(value, by: -0.1)); return .handled }
        .onKeyPress(.rightArrow) { set(FaderMath.step(value, by: 0.1)); return .handled }
        .accessibilityElement()
        .accessibilityLabel("Voice and Mac sound balance")
        .accessibilityValue(FaderMath.spokenValue(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(FaderMath.step(value, by: 0.1))
            case .decrement: set(FaderMath.step(value, by: -0.1))
            @unknown default: break
            }
        }
    }

    /// Sets the value, caught at the centre — with one tick on the trackpad as
    /// it arrives there, not again while it rests.
    private func set(_ raw: Float) {
        let snapped = FaderMath.snapped(raw)
        let centred = snapped == 0
        if centred, !isCentred {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        isCentred = centred
        value = snapped
    }
}

/// The fader's arithmetic, apart from the drawing so it can be tested.
enum FaderMath {
    /// How close to the centre counts as the centre.
    static let detent: Float = 0.06

    /// −1 at the left end of the cap's travel, 1 at the right.
    static func value(forX x: CGFloat, width: CGFloat, capWidth: CGFloat) -> Float {
        let travel = width - capWidth
        guard travel > 0 else { return 0 }
        let fraction = (x - capWidth / 2) / travel
        return Float(min(1, max(-1, fraction * 2 - 1)))
    }

    static func snapped(_ value: Float) -> Float {
        abs(value) < detent ? 0 : min(1, max(-1, value))
    }

    /// A step on the tenths, so arrow keys always come back to exactly the centre.
    static func step(_ value: Float, by delta: Float) -> Float {
        snapped(((value + delta) * 10).rounded() / 10)
    }

    static func spokenValue(_ value: Float) -> String {
        let gains = AudioMix.gains(balance: value)
        if value == 0 { return "both full" }
        return value < 0 ? "Mac sound \(Int((gains.system * 100).rounded())) %"
                         : "voice \(Int((gains.voice * 100).rounded())) %"
    }
}

/// The icon after the title, for the right-hand side of the fader.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview("Crossfader") {
    @Previewable @State var balance: Float = -0.35
    @Previewable @State var ducks = true
    AudioCrossfaderView(balance: $balance, ducksSystemAudio: $ducks, hasMicrophone: true,
                        voiceLevel: -16, voicePeak: -9, voiceClipping: false,
                        systemLevel: -12, systemPeak: -6)
        .padding()
}

#Preview("DJ fader") {
    VStack(spacing: 16) {
        DJFader(value: .constant(0))
        DJFader(value: .constant(-0.4))
        DJFader(value: .constant(1))
    }
    .padding()
}
