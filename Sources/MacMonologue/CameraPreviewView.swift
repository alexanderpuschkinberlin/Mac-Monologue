import AVFoundation
import SwiftUI

/// The one thing SwiftUI cannot draw natively: the live capture preview.
///
/// Always mirrored, like a bathroom mirror: that is what makes moving around in
/// it feel natural. Whether the *file* is mirrored is decided separately.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    /// Changes whenever the session was reconfigured and its connection may be new.
    var generation: Int = 0

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        view.applyMirroring()
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        nsView.applyMirroring()
    }

    final class PreviewNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            // Letterboxed: the whole frame is visible, never cropped.
            previewLayer.videoGravity = .resizeAspect
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func applyMirroring() {
            guard let connection = previewLayer.connection,
                  connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
            applyMirroring()
        }
    }
}
