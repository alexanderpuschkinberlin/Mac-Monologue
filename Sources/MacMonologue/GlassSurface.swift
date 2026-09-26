import SwiftUI

// Liquid Glass where macOS has it (26 and later), the materials of macOS 15
// otherwise. Standard controls - the toolbar, the sidebar, popovers - pick the
// new look up by themselves; these cover the few surfaces the app draws itself.
// Glass is for controls that float over content, never for the content: the
// preview, the fields and the meters stay as they are.

extension View {
    /// A surface for controls floating over the preview: the sound bar, the
    /// notices, the drag handle.
    @ViewBuilder
    func floatingSurface<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    /// The one prominent action of a state: Record, Resume, New Recording.
    @ViewBuilder
    func prominentActionStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// The other actions next to it.
    @ViewBuilder
    func secondaryActionStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// The bottom bar: a bar material on macOS 15; on 26 the glass buttons
    /// float on the window by themselves.
    @ViewBuilder
    func bottomBarBackground() -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            background(.bar)
                .overlay(alignment: .top) { Divider() }
        }
    }
}
