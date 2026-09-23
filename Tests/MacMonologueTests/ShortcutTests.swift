import Carbon.HIToolbox
import XCTest
@testable import Mac_Monologue

final class ShortcutTests: XCTestCase {
    func testDefaultsReadTheWayMacOSPrintsThem() {
        XCTAssertEqual(Shortcut.defaultToggle.displayString, "⌃⌥⌘R")
        XCTAssertEqual(Shortcut.defaultFinish.displayString, "⌃⌥⌘↩")
    }

    func testModifierOrderMatchesMacOS() {
        let all = Shortcut(keyCode: UInt32(kVK_ANSI_K),
                           carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey),
                           keyLabel: "K")
        XCTAssertEqual(all.modifierSymbols, ["⌃", "⌥", "⇧", "⌘"])
    }

    /// A single modifier would fire while typing in other apps.
    func testASingleModifierIsNotAcceptable() {
        let commandR = Shortcut(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: UInt32(cmdKey), keyLabel: "R")
        XCTAssertFalse(commandR.isAcceptable)
        XCTAssertTrue(Shortcut.defaultToggle.isAcceptable)
    }

    func testSurvivesBeingStored() throws {
        let data = try JSONEncoder().encode(Shortcut.defaultFinish)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), .defaultFinish)
    }
}
