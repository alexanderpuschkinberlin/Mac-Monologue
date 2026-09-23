import AVFoundation
import SwiftUI

/// The screen-mode preview: exactly the frames being recorded, bubble included.
struct LivePreviewView: NSViewRepresentable {
    /// Receives the view's sink when it appears and nil when it goes away.
    var onAttach: (PreviewSink?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onAttach: onAttach) }

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        context.coordinator.onAttach(view.sink)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    static func dismantleNSView(_ nsView: PreviewNSView, coordinator: Coordinator) {
        coordinator.onAttach(nil)
    }

    final class Coordinator {
        let onAttach: (PreviewSink?) -> Void
        init(onAttach: @escaping (PreviewSink?) -> Void) { self.onAttach = onAttach }
    }

    final class PreviewNSView: NSView {
        let displayLayer = AVSampleBufferDisplayLayer()
        lazy var sink = PreviewSink(renderer: displayLayer.sampleBufferRenderer)

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            // Letterboxed, like the camera preview: the whole frame, never cropped.
            displayLayer.videoGravity = .resizeAspect
            layer?.addSublayer(displayLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            displayLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
