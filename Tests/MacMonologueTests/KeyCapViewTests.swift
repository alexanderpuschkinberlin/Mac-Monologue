import SwiftUI
import XCTest
@testable import Mac_Monologue

@MainActor
final class KeyCapViewTests: XCTestCase {
    /// Renders every illustration the app shows, and writes them out for a person
    /// to look at — whether a drawing reads as a hand is not something to assert.
    func testIllustrationsRender() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keycaps")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let cases: [(String, Shortcut)] = [
            ("toggle", .defaultToggle),
            ("finish", .defaultFinish),
            ("right-hand-letter", Shortcut(keyCode: 45, carbonModifiers: 4096 | 2048, keyLabel: "N")),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (name, shortcut) in cases {
                let renderer = ImageRenderer(content: KeyCapView(shortcut: shortcut)
                    .padding(12)
                    .background(scheme == .dark ? Color.black : Color.white)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage, "\(name) did not render")
                let data = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation!)?
                    .representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("\(name)-\(scheme).png"))
            }
        }
        print("KEYCAP_SNAPSHOTS \(directory.path)")
    }

    func testSpokenDescriptionReadsLikeAnInstruction() {
        XCTAssertEqual(KeyCapView.spokenDescription(of: .defaultToggle),
                       "Hold Control, Option, and Command, then press R")
        XCTAssertEqual(KeyCapView.spokenDescription(of: .defaultFinish),
                       "Hold Control, Option, and Command, then press Return")
    }
}
