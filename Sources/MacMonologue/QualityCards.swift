import SwiftUI

/// The four quality steps as cards to click, each saying in plain words what it
/// is for and how big ten minutes get. Shared by the welcome steps and Settings,
/// so both explain it the same way.
struct QualityCards: View {
    @Binding var selection: VideoQuality

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                card(.economical)
                card(.medium)
            }
            GridRow {
                card(.high)
                card(.veryHigh)
            }
        }
    }

    private func card(_ quality: VideoQuality) -> some View {
        let isSelected = quality == selection
        return Button {
            selection = quality
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(quality.title).font(.headline)
                    if quality == .standard {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                Text(quality.sizeLabel)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                Text(quality.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(quality.title), \(quality.sizeLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
