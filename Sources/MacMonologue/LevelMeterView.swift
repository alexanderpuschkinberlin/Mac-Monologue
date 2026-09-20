import SwiftUI

/// −60…0 dB meter with peak-hold and a clipping indicator.
struct LevelMeterView: View {
    let level: Float
    let peak: Float
    let isClipping: Bool

    /// The clipping red from omacom/monologue (`#f06c6c`), kept deliberately:
    /// it is the one visual constant carried over verbatim.
    private static let clipColor = Color(red: 0.94, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))

                    Capsule()
                        .fill(isClipping ? Self.clipColor : Color.accentColor)
                        .frame(width: width * CGFloat(AudioLevelMeter.fraction(forDB: level)))

                    // Peak-hold marker.
                    Capsule()
                        .fill(isClipping ? Self.clipColor : Color.primary.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: max(0, width * CGFloat(AudioLevelMeter.fraction(forDB: peak)) - 2))
                }
            }
            .frame(height: 8)
            .animation(.linear(duration: 0.05), value: level)

            HStack(spacing: 0) {
                Text("−60")
                Spacer()
                if isClipping {
                    Text("Clipping")
                        .foregroundStyle(Self.clipColor)
                }
                Spacer()
                Text("0")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .help("Microphone level in dBFS, with peak hold")
    }
}
