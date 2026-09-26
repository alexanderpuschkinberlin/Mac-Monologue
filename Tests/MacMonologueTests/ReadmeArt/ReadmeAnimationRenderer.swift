import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Mac_Monologue

/// Renders every frame of the animated drawings, light and dark, when asked
/// to: `bin/render-readme-animations` sets README_ANIMATION_OUTPUT and turns
/// the frames into animated WebP. Skipped otherwise.
@MainActor
final class ReadmeAnimationRenderer: XCTestCase {
    func testRenderAnimationFrames() throws {
        guard let output = ProcessInfo.processInfo.environment["README_ANIMATION_OUTPUT"] else {
            throw XCTSkip("rendered by bin/render-readme-animations")
        }
        let root = URL(fileURLWithPath: output)

        for motif in ReadmeAnimations.all {
            for scheme in [ColorScheme.light, .dark] {
                let directory = root.appendingPathComponent("\(motif.name)-\(scheme == .dark ? "dark" : "light")")
                try? FileManager.default.removeItem(at: directory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for frame in 0..<motif.frameCount {
                    let renderer = ImageRenderer(content: AnimatedFrameView(motif: motif, frame: frame)
                        .environment(\.colorScheme, scheme))
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.cgImage, "\(motif.name) frame \(frame) did not render")
                    let url = directory.appendingPathComponent(String(format: "%04d.png", frame))
                    let destination = try XCTUnwrap(
                        CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                    CGImageDestinationAddImage(destination, image, nil)
                    XCTAssertTrue(CGImageDestinationFinalize(destination))
                }
            }
        }
    }
}
