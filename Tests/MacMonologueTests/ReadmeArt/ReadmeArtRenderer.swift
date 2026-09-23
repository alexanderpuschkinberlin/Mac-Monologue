import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Mac_Monologue

/// Renders the README illustrations, light and dark, when asked to:
/// `bin/render-readme-art` sets README_ART_OUTPUT. Skipped otherwise, so the
/// normal test run stays quick.
@MainActor
final class ReadmeArtRenderer: XCTestCase {
    func testRenderIllustrations() throws {
        guard let output = ProcessInfo.processInfo.environment["README_ART_OUTPUT"] else {
            throw XCTSkip("rendered by bin/render-readme-art")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for motif in ReadmeArt.all {
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: MotifView(motif: motif).environment(\.colorScheme, scheme))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage, "\(motif.name) did not render")
                let url = directory.appendingPathComponent("\(motif.name)-\(scheme == .dark ? "dark" : "light").png")
                let destination = try XCTUnwrap(
                    CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
            }
        }
    }
}
