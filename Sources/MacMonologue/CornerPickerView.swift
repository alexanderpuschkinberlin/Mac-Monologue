import SwiftUI

/// Four dots in the corners of a small screen outline: click one to put the
/// camera bubble there. Understandable without a single word of text.
struct CornerPickerView: View {
    @Binding var corner: BubbleCorner

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                cell(.topLeading)
                cell(.topTrailing)
            }
            HStack(spacing: 0) {
                cell(.bottomLeading)
                cell(.bottomTrailing)
            }
        }
        .frame(width: 50, height: 32)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bubble position")
    }

    private func cell(_ candidate: BubbleCorner) -> some View {
        Button {
            corner = candidate
        } label: {
            Circle()
                .fill(candidate == corner ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(candidate))
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.accessibilityLabel)
        .accessibilityAddTraits(candidate == corner ? .isSelected : [])
    }

    private func alignment(_ corner: BubbleCorner) -> Alignment {
        switch corner {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}
